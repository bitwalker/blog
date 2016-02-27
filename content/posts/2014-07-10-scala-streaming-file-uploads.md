+++
date = "2014-07-10T10:30:05-05:00"
draft = false
title = "Proxied Streaming Uploads with Scala/Play"
categories = ["play", "scala", "programming"]

+++

I recently was working on a project using a mashup of technologies: Scala, Play Framework, Sqrrl/Accumulo, Microsoft SQL Server, Hadoop/HDFS, Hive, and some others. Needless to say, rampup was a bit like swallowing water from a firehose. I was brought on to help get a release completed by it's deadline, so I wasn't on the project for more than a month, but I did encounter one very fun problem that I felt like sharing. To briefly summarize the context: The project was composed of two Play applications, a web frontend, which served up the assets for the UI and handled proxying requests to the API, which was behind a firewall, and therefore not accessible from the internet. Users needed to be able to upload files containing potentially sensitive data, of varying types, and of unrestricted size (though I would guess the average file size would hover between 25-100mb). These files were ultimately stored in HDFS, behind yet another firewall, which is only accessible by the API server. Not your average file upload scenario.

## The Scenario

So the requirements are as follows:

- Files cannot be stored on the web or API server (potential security risk)
- Files should not be stored in memory during uploads, due to the combination of large file sizes and potential for large amounts of concurrent uploads consuming too much of the servers memory.
- The final destination of the files is HDFS.
- Files also need to be downloadable, with the same constraints

My final solution was the following:

- Write a custom streaming body parser for streaming uploads from the client straight to the API server
- Write a custom streaming body parser for streaming uploads from the web server directly to HDFS
- Use Apache Tika to detect content type of the upload, and store that with other metadata in SQL
- When a download of a file is requested, use a custom iteratee from the web server to stream the chunked response data  from the API, straight to the client, while preserving the response headers containing file metadata.

What initially seemed relatively straight forward, turned out to be one of the most complex but interesting bits of code I've written in quite some time. There's a lot of code coming, because I'd like to share the entire solution (with project-specific bits stripped out), so buckle up.

## Stage 1 - Client -> Web

Let's begin with the first stage of the upload process, streaming files from the client to the API, via the web application. First, we have our controller:

```scala
package controllers

import play.api.mvc._
import controllers.traits.Secured
import util.parsers.StreamingBodyParser._

object ApiProxyController extends Controller with Secured {

  def makeFileUploadRequest(endpointPath: String) = AuthenticatedAction(streamingBodyParser(endpointPath)) {
    (request) => {
      val uploadResult = request.body.files(0).ref
      uploadResult.fold(
        err     => BadRequest(err.errorMessage),
        success => Ok(success.body)
      )
    }
  }

}
```

The only things to note here are that we do user authentication at this point, using a custom action, which takes an implementation of `BodyParser`. The custom streaming body parser needs to know the endpoint we're sending the file to, so we use a partially applied constructor function in order to provide that information. The body of the action here is executed once parsing of the body has completed, so all we have to do at that point is check the result of the upload, which in this case is an instance of `Either[StreamingError, StreamingSuccess]`.

Next, we have our custom streaming body parser. This is a big one, so I'm going to use comments in the code to describe notable features instead of showing you code and then talking about it. I'll summarize some things before moving on though.

```scala
package util.parsers

import play.api.mvc.{BodyParser, RequestHeader}
import play.api.mvc.BodyParsers.parse
import parse.Multipart.PartHandler
import play.api.mvc.MultipartFormData.FilePart
import java.io.{PrintWriter, OutputStreamWriter, OutputStream}
import java.net.{URL, URLConnection, HttpURLConnection}
import play.api.libs.iteratee.{Cont, Done, Input, Iteratee}
import models.{ApiRequest, AuthUser}

/**
 * These two classes represent the success or failure result of the upload,
 * if it succeeded, StreamingSuccess.body will contain the response body from
 * the API. If it fails, StreamingError.errorMessage will contain the error message
 * received in the response body.
 */
case class StreamingSuccess(body: String)
case class StreamingError(errorMessage: String)

/**
 * This companion object contains the constructor for our custom BodyParser,
 * as well as the logic for constructing the output stream to the API.
 */
object StreamingBodyParser {
  /**
   * If you recall, we partially apply the API endpoint path in the controller when providing
   * the request body parser to use. In turn, the action will invoke the partial function
   * when it begins parsing the request.
   */
  def streamingBodyParser(endpointPath: String) = BodyParser { request =>
    // Use Play's built in multipart/form-data parser, with our own FilePartHandler.
    // Essentially, Play will handle parsing the normal form data, we'll handle parsing the file
    parse.multipartFormData(new StreamingBodyParser(streamConstructor(endpointPath, request))
      .streamingFilePartHandler(request))
      .apply(request)
  }

  /**
   * This function constructs an HttpURLConnection object to the provided endpoint path,
   * with the necessary authentication headers, as well as headers to setup the chunked
   * streaming mode. As you may have noticed, it's intended to be partially applied by
   * first providing the endpoint path and request object, then invoking the resulting
   * function when we want to produce the connection object.
   */
  private def streamConstructor(endpointPath: String, request: RequestHeader): Option[HttpURLConnection] = {
    // This is a bit of project-specific logic, but basically we're validating
    // that the request is authenticated before opening the request to the API
    AuthUser.buildFromSession(request.session) match {
      case Some(user) => {
        // Again, internals, all we're doing here is building the authentication headers,
        // for example, Authorization, with the API token for the user
        val headers = ApiRequest.buildRequest(request, user.authToken).buildHeaders

        // Construct the request connection to the API. It will always be a POST, with
        // chunked streaming mode enabled, with 1mb chunks, with output enabled
        val url = new URL(config.Global.API_ENDPOINT + endpointPath)
        val con = url.openConnection.asInstanceOf[HttpURLConnection]
        con.setRequestMethod("POST")
        con.setChunkedStreamingMode(1024)
        con.setDoOutput(true)

        // Set auth headers
        headers.foreach { header =>
          con.setRequestProperty(header._1, header._2)
        }

        // Pass along request headers
        request.headers.toSimpleMap.foreach(h => con.setRequestProperty(h._1, h._2))

        Some(con)
      }
      case None => None
    }
  }

}

// Our custom BodyParser's constructor takes a function which produces an HttpURLConnection.
class StreamingBodyParser(streamConstructor: () => Option[HttpURLConnection]) {

  /**
   * This "handler" function actually produces a function which is the
   * actual handler executed by Play when parsing files in the request.
   */
  def streamingFilePartHandler(request: RequestHeader):
          PartHandler[FilePart[Either[StreamingError, StreamingSuccess]]] = {
    // An execution context is required for the Iteratee below
    import play.api.libs.concurrent.Execution.Implicits._

    val CRLF = "\r\n"

    // This produces the PartHandler function which is consumed by Play's
    // multipartFormData body parser.
    parse.Multipart.handleFilePart {
      case parse.Multipart.FileInfo(partName, filename, contentType) =>
        // Reference to hold the error message if one is produced
        var errorMsg: Option[StreamingError] = None

        // Get the HTTP connection to the API
        val connection = streamConstructor(filename).get

        // Set content-type property for the API request
        val boundary = System.currentTimeMillis().toHexString
        connection.setRequestProperty("Content-Type", "multipart/form-data; boundary=" + boundary)

        /**
         * Create the output stream. If something goes wrong while trying to instantiate
         * the output stream, assign the error message to the result reference, e.g.
         *    `result = Some(StreamingError("network error"))`
         * and set the outputStream reference to `None`; the `Iteratee` will then do nothing
         * and the error message will be passed to the `Action`.
         */
        val outputStream: Option[OutputStream] = try {
          Some(connection.getOutputStream())
        } catch {
          case e: Exception => {
            errorMsg = Some(StreamingError(e.getMessage))
            None
          }
        }

        // Create print writer for writing out multipart form data
        val writer = outputStream match {
          case Some(os) => {
            val pw = new PrintWriter(new OutputStreamWriter(os))
            val charset = "UTF-8"
            // Send form parameters.
            request.queryString.foreach { queryStrings =>
              pw.append("--" + boundary)
                .append(CRLF)
                .append("Content-Disposition: form-data; name=\"" + queryStrings._1 + "\"")
                .append(CRLF)
                .append(s"Content-Type: text/plain; charset=$charset")
                .append(CRLF)
                .append(CRLF).append(queryStrings._2.mkString)
                .append(CRLF)
                .flush()
            }

            // Send binary file header
            pw.append("--" + boundary)
              .append(CRLF)
              .append("Content-Disposition: form-data; name=\"file\"; filename=\"" + filename + "\"")
              .append(CRLF)
            val fileType = URLConnection.guessContentTypeFromName(filename)
            pw.append("Content-Type: " + contentType.getOrElse(fileType)
              .append(CRLF)
              .append("Content-Transfer-Encoding: binary")
              .append(CRLF)
              .append(CRLF)
              .flush()
            Some(pw)
          }
          case None => None
        }

        /**
         * This is the interesting bit. This fold function pumps file data from
         * the input stream to the output stream in chunks. Each step will receive
         * one of the Input types, which determines whether we are done parsing, should
         * skip the current chunk (Empty), or call the parser on the chunk before
         * continuing. You can think of this as a reduce operation on the input
         * stream, using the output stream as the accumulator, where each reduction
         * pushes the chunk of data received from the input stream to the output stream.
         */
        def fold[E, A](state: A)(f: (A, E) => A): Iteratee[E, A] = {
          def step(s: A)(i: Input[E]): Iteratee[E, A] = i match {
            // Hit EOF, we're done parsing
            case Input.EOF   => Done(s, Input.EOF)
            // If the chunk is empty, skip this chunk and continue
            case Input.Empty => Cont[E, A](i => step(s)(i))
            // We have a non-empty chunk, so call our parser function `f` with the data.
            case Input.El(e) => {
              val s1 = f(s, e)
              // if an error occurred, set Iteratee to Done
              errorMsg match {
                case Some(result) => Done(s, Input.EOF)
                case None => Cont[E, A](i => step(s1)(i))
              }
            }
          }
          Cont[E, A](i => step(state)(i))
        }

        /**
         * And here is where we make use of the fold function from above. We
         * give it the output stream as it's accumulator, and a callback function which
         * takes two parameters, the current state of the Iteratee (the output stream)
         * and the data to parse, which will be a byte array. This produces an Iteratee,
         * which will eventually produce Option[OutputStream] as it's result. We map over
         * the Iteratee (called when the Iteratee is finished executing) in order to clean
         * up the resources used, write out the last bit of form data, and get the response
         * from the API.
         */
        fold[Array[Byte], Option[OutputStream]](outputStream) { (os, data) =>
          os.foreach { _.write(data) }
          os
        }.map { os =>
          // Flush the output stream
          os.foreach { _.flush }
          // Write out the end of the multipart form-data
          writer.foreach { w =>
            w.append(CRLF).flush
            w.append("--" + boundary + "--").append(CRLF).flush
          }
          // Close the stream and return the final result
          os.foreach { _.close }
          errorMsg match {
            case Some(result) => Left(result)
            case None =>
              // Check the result for errors
              val responseCode = connection.getResponseCode
              if (400 <= responseCode && responseCode < 600) {
                val errorResponse = connection.getErrorStream
                val error = scala.io.Source.fromInputStream(errorResponse).mkString
                Left(StreamingError(s"$responseCode: $error"))
              } else {
                val responseStream = scala.io.Source.fromInputStream(connection.getInputStream)
                Right(StreamingSuccess(responseStream.mkString))
              }
          }
        }
    }
  }
}
```

So hopefully I haven't lost you. Just to recap, we're using a custom BodyParser in order to provide our own FilePartHandler. The former is required for any controller action in a Play application in order to properly parse the request body, the latter is used specifically in multipart/form-data requests to handle binary file data. The FilePartHandler uses iteratees to handle each FilePart (chunk of data, usually a byte array). Iteratees are a method for sequentially processing input data with accumulated state. In the case above, the accumulated state will always be the output stream, because at each step of the sequence, we're just pushing the data in to the output stream. Another way of thinking about it is to consider the output stream a type of collection. If instead of an output stream, we had used an array, when the iteratee finished executing, we'd have a byte array of the file data instead of an output stream.

So at this point we've received a request to upload a file from the user, authenticated them, opened a proxied request to the API, and started pumping file data through. It's about to get even more fun :)

## Stage 2 - Web -> API

The next step is receiving the request from the web server to the API. From the perspective of the API server, the request is no different than if it came from a browser. Again we'll have a custom BodyParser, one which is different enough that I'll show the code for it as well, but I'll strip out any duplicate information. A key difference here is that the API is not proxying the request to another web server (at least from it's perspective). Instead, it contains an abstraction around how it stores uploads. This abstraction is defined via the StorageProvider trait, which is injected at runtime with either a local file storage provider, or an HDFS provider. I'm not going to show the concrete implementations of these providers, since they are pretty straightforward, but I will show you the trait, since it's key to understanding how we've abstracted away the concept of storage within the API.

Let's start with the StorageProvider trait:

```
package util.storage

import config.ConfigFactory
import play.api.libs.iteratee.Enumerator

trait StorageProvider extends ConfigFactory {

  /**
   * Write a file to storage
   * @param data The byte data to write
   * @param fileName The name of the file once stored
   */
  def writeFile(data: Array[Byte], fileName: String)

  /**
   * Gets a stream to the provided filename which can be written to
   * @param fileName The name of the file to stream data to
   */
  def getWriteableStream(fileName: String): StreamableResource

  /**
   * Read a file and return it in an Array[Byte].
   * @param fileName The name of the file to read
   * @return
   */
  def readFile(fileName: String): Array[Byte]

  /**
   * Given a filename, produce an Enumerator[Array[Byte]] for streaming the file to the consumer
   * @param fileName The name of the file to stream
   * @return
   */
  def getReadableStream(fileName: String): Enumerator[Array[Byte]]

  /**
   * Delete a file from storage
   * @param fileName The name of the file to delete
   */
  def deleteFile(fileName: String)

  /**
   * Detect a given file's content type
   * Uses a combination of reading markers in the file's header,
   * as well as taking the extension into account if markers aren't
   * enough. Returns application/octet-stream if no type can be determined
   * @param fileName
   * @return
   */
  def getFileType(fileName: String): String
}
```

Nothing special there, pretty much just an abstraction around typical file operations we all use day to day. As long as your implementation has the ability to open input/output streams, and read/write/delete files, you can store files however you want.

Next up, you'll need to know about this small class, `StreamableResource`:

```scala
case class StreamableResource(stream: Option[OutputStream], resource: Option[Closeable]) extends Closeable {
  override def close = resource.foreach(_.close)
}
```

This exists because a StorageProvider implementation likely has a resource connected to the open stream, which will need to be properly cleaned up when streaming is complete.

Alright, let's dig in to the controller!

```scala
package controllers

import util.storage.StorageProvider
import util.controller.ApiSecuredController
import play.api.mvc._
import javax.inject.{Inject, Singleton}
import providers._
import play.api.Logger
import util.parsers.StreamingBodyParser._

@Singleton
class ApiController @Inject()(
  fileProvider:    FileProvider,
  storageProvider: StorageProvider
) extends Controller with ApiSecuredController {

  /**
   * Similarly to before, e're creating a new instance of our custom BodyParser, which takes
   * a function receiving a StorageProvider, and producing a StreamableResource
   */
  def uploadFile() = Action(streamingBodyParser(streamConstructor(storageProvider))) {
    (request) => {
      // Act on the result of parsing/storing the uploaded file
      request.body.files(0).ref.fold(
        // Parsing/storing failed
        err     => BadRequest(err.errorMessage),
        // Parsing/storing succeeded
        success => {
          // If you need access to the form parameters...
          val params = request.body.asFormUrlEncoded
          // Save metadata record for file
          try {
            val contentType = storageProvider.getFileType(success.filename)
            val metadata    = fileProvider.createFile(contentType, success.filename)
            Ok(Json.toJson(metadata.id))
          } catch {
            case e: Exception =>
              Logger.error(s"Failed to create file: ${e.getMessage}")
              BadRequest(e.getMessage)
          }
        }
      )
    }
  }
}
```

And now for the API's custom body parser:

```
object StreamingBodyParser {
  /**
   * The main difference here is that we are generating our output stream differently than in the
   * web project.
  def streamingBodyParser(getStream: String => Option[StreamableResource]) = BodyParser { request =>
    parse.multipartFormData(new StreamingBodyParser(getStream).streamingFilePartHandler(request))
      .apply(request)
  }

  /**
   * Here is where that difference is implemented. Our stream constructor takes a StorageProvider instance, and
   * returns a function that when called with a filename, will open an output stream to that file, and return it
   * wrapped as a StreamableResource.
   */
  def streamConstructor(storageProvider: StorageProvider)(filename: String): Option[StreamableResource] = {
    Some(storageProvider.getWriteableStream(filename))
  }
}

class StreamingBodyParser(streamConstructor: String => Option[StreamableResource]) {

  def streamingFilePartHandler(request: RequestHeader):
        PartHandler[FilePart[Either[StreamingError, StreamingSuccess]]] = {
    /**
     * Most of the following is either the same or similar to the web project's
     * implementation, I'll highlight the important changes with comments.
     */
    import play.api.libs.concurrent.Execution.Implicits._

    parse.Multipart.handleFilePart {
      case parse.Multipart.FileInfo(partName, filename, contentType) =>

        // Get StreamableResource by invoking streamConstructor
        // Get output stream from StreamableResource
        // Define fold function, same as before

        /**
         * This is almost identical to the web implementation, but
         * closes the StreamableResource as well as the output stream.
         * It also doesn't need to read any kind of response, so there's
         * a lot less going on.
         */
        fold[Array[Byte], Option[OutputStream]](outputStream) { (os, data) =>
          os foreach { _.write(data) }
          os
        }.map { os =>
          os foreach { _.close }
          streamResource foreach { _.close }
          errorMsg match {
            case Some(result) =>
              // Failed
              Left(result)
            case None =>
              // Succeeded
              Right(StreamingSuccess(filename))
          }
        }
    }
  }
}
```

So the above closes the loop on our file upload process. The client makes a request to the web server, the request body is read in chunks and piped via a new request to the API server, the API server reads the request body in chunks, and pipes that data via the storage provider to it's final destination. During the whole process, the file itself is never stored in memory.

What about downloads though? Let's take a look:

## Downloading Files

Let's start with the API controller action first on this one, since it's the simplest:

```scala
/**
 * As you may have noticed in the upload portion, we're storing file metadata
 * in the database, and returning the ID to the client. That is the id used in
 * this request.
 */
def downloadFile(fileId: Long) = Action(parse.anyContent) {
  (request) => {
    fileProvider.getFile(fileId) match {
      case Some(file) => {
        /**
         * Nothing to crazy here, we're telling Play to stream the
         * response body, using the stream provided by the storage provider,
         * and ensuring that the content-type header is set properly
         */
        SimpleResult(
          header = ResponseHeader(200, Map(CONTENT_TYPE -> file.fileType)),
          body = storageProvider.getReadableStream(file.fileName)
        )
      }
      case None => {
        NotFound
      }
    }
  }
}
```

The interesting bit is here in the web project's controller action:

```scala
def makeFileDownloadRequest(endpointPath: String) = AuthenticatedAction(parse.anyContent) {
  (request) => {
    import play.api.libs.concurrent.Execution.Implicits._
    import play.api.libs.iteratee.{Input, Iteratee}
    import scala.concurrent.{promise, Await}
    import scala.concurrent.duration._

    // First we have to create a new request, containing all the required headers
    val user        = AuthUser.buildFromSession(request.session).get
    val authHeaders = ApiRequest.buildRequest(request, user.authToken).buildHeaders.toMap
    val reqHeaders  = request.headers.toSimpleMap
    val apiHeaders  = reqHeaders ++ authHeaders
    var url = WS.url(config.Global.API_ENDPOINT + endpointPath)
    apiHeaders.foreach { case (key, value) => {
      url = url.withHeaders(key -> value)
    }}

    // Create promises for the iteratee over file data, and the result
    val iterateePromise = promise[Iteratee[Array[Byte], Unit]]
    val resultPromise = promise[SimpleResult]

    // Make the download request to the API
    val req = url.get { responseHeaders: ResponseHeaders =>
      // Resolve the result promise using the response from the API
      resultPromise.success(
        Ok.stream({content: Iteratee[Array[Byte], Unit] =>
          // Resolve the iteratee promise with the client output iteratee
          iterateePromise.success(content)
        }).withHeaders(
          "Content-Type" -> responseHeaders.headers.getOrElse("Content-Type", Seq("application/octet-stream")).head,
          "Connection"->"Close",
          "Transfer-Encoding"-> responseHeaders.headers.getOrElse("Transfer-Encoding", Seq("chunked")).head
        )
      )
      // Run the iteratee for the response to the client
      Iteratee.flatten(iterateePromise.future)
    }
    // Handle request completion by sending EOF to the client
    req.onSuccess {
      case ii => ii.feed(Input.EOF)
    }
    // Handle request failure
    req.recover {
      case t: Throwable => {
        resultPromise.tryFailure(t)
      }
    }
    // Return control back to Play for handling
    Await.result(resultPromise.future, 30 seconds)
  }
}
```

It's a bit hard to follow with all the promises, futures, iteratees, etc - but the gist is that as soon as we get response headers from the API, we'll send those to the client, with status code 200, specifying a chunked transfer encoding, as well as the content type for the response body. As the response body from the API begins to download, it will pipe the chunked data straight into the response to the client. Unfortunately, it's not very intuitive code to read, and this section of code is the one that has me constantly double checking my work to make sure I didn't mess something up - it just doesn't read as naturally as I would like.


## Final thoughts

I have some ideas around how this might be improved. For one, I feel like it should be possible to extract the proxied request logic from the web server's StreamingBodyParser into an implementation of StorageProvider, and thereby use a single StreamingBodyParser implementation. I haven't dug in to that to see what the gotchas might be though. I haven't done any performance benchmarks, but in my testing it seemed like uploads and downloads were snappy. Overall I feel like it's a fairly solid solution, but I'm waiting to see where it breaks once heavy load becomes more of a concern.

If you have improvements, thoughts, whatever, please leave a comment!
