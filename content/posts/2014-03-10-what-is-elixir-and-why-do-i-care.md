+++
title = "What Is Elixir, and Why Do I Care?"
draft = false
date = "2014-03-10T17:52:37-05:00"
categories = ["elixir", "erlang", "programing", "tutorials"]
+++

This was the first thing that sprung to my mind when I first heard about Elixir. Up until that point I had written significant code in a number of languages and platforms, looking for one that *felt right*, if that's even the best way to phrase the nature of my search. C#, Ruby, Python, Javascript, Scala, Clojure, C and C++ - all of them shared one theme in common: I enjoy some aspect of them, each has their pros and cons, I was able to program effectively in them, and generally the communities are great. So why would Elixir be any different? Why bother to learn yet another language that I'll be just as frustrated with?

Being the person I am, I decided to try it anyway, because hey, what do I have to lose, right? Boy, am I glad I did. Elixir steals what is great about many of the languages I already know and love, adds some great features of its own, and combines them with an extremely powerful, yet little-known language/platform known as Erlang/OTP.

## Erlang

Before I start talking about Elixir, I want to make a note here about Erlang. You may or may not have heard about this language before, but don't let that fool you. Erlang, and its standard library, OTP, are used in production all over the world, most notably in the telecommunications industry where it powers a great deal of the systems all of us with a cell phone rely on. It was designed in the 80s by a team at Ericsson, to replace their aging systems with something that was incredibly fault-tolerant, trivial to write concurrent sofware in, and easily distributable (code you write should run on one node the same as it runs on 100, with no code changes). Today, Erlang powers software such as WhatsApp, Facebook Chat, Chef, Heroku, CouchDb, Riak, RabbitMq, and more. I [watched a talk](https://www.youtube.com/watch?v=_VKGOTl3jGg) not too long ago where a nuclear physicist had written a complex system to manage a neutrino experiment in a remote region, deep underground. He chose Erlang because of its fault tolerance capabilities, which would ensure that if the system crashed for some reason, it could self-heal, and also log information about the process that crashed, so the experiment could go on while he studied the failure. It is upon Erlang and OTP that Elixir is written, and everything Erlang provides is readily available in Elixir.

## Elixir's Elevator Pitch

Elixir is a functional, metaprogrammable language, built for productivity, extensibility, and to take advantage of Erlang's simple but powerful fault-tolerance and concurrency primitives. It is composed of a simple core language, with syntax that is very reminiscent of Ruby (and no wonder, as its creator José Valim, is a Ruby core committer, and author of many Ruby libraries such as Devise). However, despite the aesthetic similarity to Ruby, the semantics of Elixir are quite different.

At a high level, Elixir provides the following features:

- Modules
- First-class functions
- Pattern matching (amazing)
- Protocols, which provide polymorphism for your data types.
- Macros. If you dig in to Elixir's source code, you will see that the vast majority of the language's syntax is actually defined as simple Elixir macros: `if`, `unless`, `cond`, etc. Incredibly powerful feature.
- Everything is an expression, this makes it easy to compose code without intermediate variables.
- [Immutability](https://deveo.com/blog/2013/03/22/immutability-in-ruby-part-1/)
- Pipes. Instead of defining code inside-out like: `Date.shift(Date.new({2014, 10, 5}), days: 10)`. Pipes allow you to write it as you would say it: `{2014, 10, 5} |> Date.new |> Date.shift(days: 10)`. Code becomes very easy to read.
- Dead simple concurrency.
- Dead simple clustering/distribution.
- Built-in unit testing
- First-class documentation (including the ability to test the code examples in your docs!)
- Excellent build tool (modeled after Leiningen for Clojure, very similar to Rake for Ruby)
- Excellent documentation and community

## Elixir Basics

Ok, so if at this point you aren't convinced, then hopefully seeing some code will do so! Let's run through the very basics you'll need to understand some Elixir code, and then I'll show you an example program which shows you how easy it is to write concurrent software in Elixir.

#### Installing Elixir

Make sure you have [Erlang R16B03](https://www.erlang-solutions.com/downloads/download-erlang-otp) installed. If you are on OSX, this step is taken care of for you by Homebrew. If you are on Linux, it should be available via your package manager (it is on Ubuntu at least).

- OSX: Simply `brew install elixir`. If you don't have [homebrew](http://brew.sh/) installed, you should.
- Fedora: `sudo yum -y install elixir`
- Arch Linux: `yaourt -S elixir`
- Gentoo: `emerge --ask dev-lang/elixir`
- Windows: `cinst elixir`. If you don't have [chocolatey](http://chocolatey.org) installed, you should.

For other operating systems, Elixir provides precompiled releases [here.](https://github.com/elixir-lang/elixir/releases/) Alternatively, you can compile from source (after installing Erlang, which should be available via your package manager), but you shouldn't need to do this.


#### Interactive Elixir

Now that you have Elixir installed, you can play around with the language most easily by using Elixir's interactive prompt, or REPL, called Interactive Elixir, or `iex` for short. Assuming Elixir is in your PATH, you can open it up like so:

```elixir
> iex
Erlang/OTP 17 [RELEASE CANDIDATE 1] [erts-6.0] [source-fdcdaca] [64-bit] [smp:4:4] [async-threads:10] [hipe] [kernel-poll:false]

Interactive Elixir (0.13.0-dev) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)>
```

As I walk through the language with you, feel free to type in the examples in the prompt and play around with different variations to get a feel for working in here. `iex` is a great way to experiment, and its [excellent help feature makes it so you never have to leave the prompt to look up documentation](http://i.imgur.com/kXgGfOl.gif).

#### Data Types

Elixir has the usual basic data types: strings, integers/floats, booleans, as well as others you may recognize:

- Tuples

```elixir
iex> tuple = {1, "test", [1, 2, 3]}
{1, "test", [1, 2, 3]}
```
- Lists

```elixir
iex> list = [1, 2, 3]
[1, 2, 3]
```

- Maps (Only available in Elixir 0.13+/Erlang R17.0-rc2). If you want to use maps, you'll currently need to compile Erlang and Elixir from source. v0.13 is going to be released soon, so if you aren't super keen on undertaking that process, you won't have to wait long.

```elixir
iex> map = %{key: "value"}
%{key: "value"}
```

- Ranges

```elixir
iex> range = 1..10
1..10
```

- Regexes

```elixir
iex> regex = ~r/^(\d)+$/
~r"^(\\d)+$"
```

It also has some types you may not be familiar with:

- Atoms (their name is their value, they are also used to reference Erlang modules)

```elixir
iex> atom = :atom
:atom
iex> :calendar.local_time()
\{\{2014, 3, 6}, {22, 13, 22\}\}
```

- Binaries

```elixir
iex> <<50, 74, 35>>
"2J#"
```

You may be going like "whaaaat" after that last one, but there's three things here. 1.) Elixir strings are implemented using binaries, 2.) binaries containing all printable characters are printed as strings in `iex`, and 3.) binaries are a more general data type that contain, well, binary data. Reading a file from disk, or data from a network connection, happen using binaries.

#### Pattern Matching

One of the most basic tools you will use when writing Elixir code is pattern matching. In short, it allows you to destructure data by its pattern. This is more easily explained using code:

```elixir
iex> {a, 2, _} = {1, 2, 3}
{1, 2, 3}
iex> a
1
iex> {a, 3, _} = {1, 2, 3}
** (MatchError) no match of right hand side value: {1, 2, 3}
```

As you can see, we asserted that the left hand side matches the right hand side using the `=` sign. When the left hand is simply a variable name, the right hand side is assigned to the left. If the left hand side is a pattern, as it is above, then it will attempt to match the pattern on the left with the value on the right, and will bind variables on the left if names instead of values are in the pattern. The underscore is used to ignore a value, and essentially says "I don't care about the value in this location". Pattern matching is an incredibly powerful feature that lets us quickly access the data we care about, while simultaneously performing validation of its structure. It's even more powerful when combined with `case`:

```elixir
case do_something() do
  {:ok, result} -> result
  {:error, _}   -> raise "We've failed!"
  _             -> raise "We got something totally unexpected back!"
end
```

It can also be used to define polymorphic functions, or functions which more concisely express their behavior under certain conditions:

```elixir
# Public API
def  sum(collection),           do: sum(collection, 0)
# Private API
defp sum([], total),            do: total
defp sum([head | rest], total), do: sum(rest, head + total)
```

In the above example, we are summing a list of integers. The first case defines what happens when `sum` is passed an empty list. The second defines what to do when give a list of at least one element. It breaks the list into two parts, its first element, or head, and the rest. We then recursively call `sum` with the tail of the list and add the result to the head to get our sum. Elixir is tail-recursive, so this function will never blow the stack, even if given a huge list of numbers.

## A Taste of Elixir

This post is getting really long, so let's ramp up the speed a bit. I'm going to show you a quick bit of example code, and then break down what it's doing, the syntax of various components, and why this is so much cleaner than its counterpart in other languages would be. This will expose you to not only some great things about Elixir, but also a wide array of its language features in one go:

```elixir
defmodule ContactsProcessor do
  @moduledoc """
  Reads in a file of contact data, and transforms each line
  into an Elixir datastructure.
  """

  @doc """
  Processes the given file.
  """
  def process(file_path) do
    File.read!(file_path)
    |> String.split("\n")
    |> Enum.filter(fn line -> String.length(line) > 0 end)
    |> Enum.map(&transform/1)
  end

  @doc """
  Transforms each line of the contacts file into a map
  of names and emails.

  ## Example

    iex> FileProcessor.transform("Paul Schoenfelder, pschoenf@nerdery.com, 123-456-7890")
    %{name: "Paul Schoenfelder", email: "pschoenf@nerdery.com"}

  """
  def transform(line) do
    [name, email, _] = line |> String.split(",") |> Enum.map(&String.strip/1)
    %{name: name, email: email}
  end
end
```

Phew! Ok, I hope I didn't lose you, I know you have some questions. Let's talk real quickly about the new stuff up there. To start with, we defined a new module. Elixir breaks logical units of code into modules. You can import modules, alias them to new names, and even pull functions in to the current module as if they were locally defined functions.

I'm sure you noticed that documentation is highly encouraged in Elixir, with first class attributes for module and function-level docs. There is a tool in Elixir's ecosystem that will take those docs and generate HTML documentation for you as well. Docs take whatever you put in them, but markdown is the rule. If you put example code in your docs, using the `iex` convention like I used above, you can tell Elixir to run its unit tests against that code, and it will validate that they are correct along with all of your other tests!

So this module does a very simple thing, it reads a file of contacts, where each contact's info is comma-separated. It then transforms those lines into a usable Elixir data structure which we can then use elsewhere. The `process` function does the meat of the work here. Befort we talk about what it's doing, a couple of features should be pointed out. The first is the use of `|>`. This operator is called pipe. It does sort of what it sounds like: it pipes the result of the left hand side, into the right hand side function as its first argument. Additional arguments can be defined as part of the right-hand side function call, but will take the place of the 2nd argument, and so on. This allows us to read our code in the same way that the data will flow. The next item to point out is the use of `fn .. end` to define an anonymous function. It should be relatively clear, but the format is as follows: `fn arg1, arg2, .. -> function_body end`. The third and last item in `process` that I'd like to point out is the `&transform/1` function application syntax. This syntax is used to pass a named function to another function. Its format is as follows: `&function_name/arity`. Any time you refer to a function in Elixir (or Erlang), the combination of name and arity matter. This is how Elixir knows which function you are referring to, specifically. At a high level, `process` is reading in the file, splitting on newlines so that we now have a list of strings (lines), we call `Enum.filter` to filter out any empty lines, and then map `transform` over each line to extract the contact information to a map. Simple, right?

The `transform` function is also simple, but let's walk through it. I am pattern matching on the result of splitting the line on commas and stripping extra whitespace from each part. This is being done by piping the line into `String.split`, then mapping `String.strip` over each part. The result should be a list containing 3 strings: name, email, and phone number, but at this point in time I don't care about the phone number, so I ignore it. I'm then creating a new map containing the contact's name and email address, which is the final result of this function.

And that's it! In other languages, I think you'd be hard pressed to so concisely define this same behavior, without a significant amount of additional boilerplate, or sacrificing readability. I'm not handling all of the possible failure conditions here, but my example assumes that the equivalent in another language wouldn't be either.

This example doesn't show Elixir's most powerful features: concurrency and distribution, but I hope you will trust me that the code you write for those scenarios is no less understandable than that which I've written above. Elixir is a powerful tool, and I wish I had the time (and space!) to write about more of its features. All I can do is encourage you to look into this language yourself, and I hope to see you in the community!
