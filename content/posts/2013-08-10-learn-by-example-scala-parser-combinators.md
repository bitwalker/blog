+++
title = "Learn by Example: Scala Parser Combinators"
draft = false
date = "2013-08-10T22:28:00-05:00"
categories = ["scala", "programming", "tutorial"]

+++

One of the more common things you run into during software development is the need to parse arbitrary text for data.
Typically, you might use regular expressions, or encode assumptions about the data format in the way you parse the text (think slicing a string at specific indices, splitting on commas, etc). Both of these are brittle, and require a lot of verbose code to properly handle all of the possible failure points. This might lead you to writing your own parser if you are committed enough - but this is a large undertaking for most developers. You have to learn how to write a parser, or learn a parser generator in order to even begin coding the solution to your particular use case. Scala has a fantastic solution to this problem however, and that solution is parser combinators.

## What Are Parser Combinators

Let's start first by breaking down the term into it's parts, parsers and combinators, and explaining what they are in case you aren't up to speed. A parser is a function that takes a stream of input tokens, and converts them into a format (typically a data structure, such as a list or a tree) that is more easily consumed by your application. A combinator is simply a higher order function which combines two functions into a new function. So a parser combinator is just a function which combines two parsers into another parser.

## How To Use Them

We are going to build a [Reverse Polish Notation](http://en.wikipedia.org/wiki/Reverse_Polish_notation) calculator as an example of how to apply parser combinators to a problem, so let's start simple and build up. First, I want to go over the available combinators we're going to use in this example:


- `|` is the alternation combinator. It says "succeed if either the left or right operand parse successfully"
- `~` is the sequential combinator. It says "succeed if the left operand parses successfully, and then the right parses successfully on the remaining input"
- `~>` says "succeed if the left operand parses successfully followed by the right, but do not include the left content in the result"
- `<~` is the reverse, "succeed if the left operand is parsed successfully followed by the right, but do not include the right content in the result"
- `^^`=> is the transformation combinator. It says "if the left operand parses successfully, transform the result using the function on the right"
- `rep` => simply says "expect N-many repetitions of parser X" where X is the parser passed as an argument to `rep`

Now that we've covered what the available combinators are, our first step is to define how to parse a number:

```scala
import scala.util.parsing.combinator._

class ReversePolishCalculator extends JavaTokenParsers {
    def num: Parser[Float] = floatingPointNumber ^^ (_.toFloat)
}
```

So, we import the parser combinators, and create a class with just our number parser for now. We extend JavaTokenParsers in order to bake in the ability to parse some text, and to gain access to the `floatingPointNumber` parser. The `num` function will match any floating point number, and convert it to a Float. The `floatingPointNumber` parser simply matches text, it doesn't do any conversion. If you were to look at the source for it, you would see that it is simply a regular expression parser:

```scala
trait JavaTokenParsers extends RegexParsers {
    def floatingPointNumber: Parser[String] = {
        """-?(\d+(\.\d*)?|\d*\.\d+)([eE][+-]?\d+)?[fFdD]?""".r
    }
}
```

So at this point, our parser can match a number, that's it. If that's all we wanted, we could wire up a quick console app to parse floats like so:

```scala
object Calculator extends ReversePolishCalculator {
    def main(args: Array[String]) {
        val result = parseAll(num, args(0))
        println(s"Parsed $result")
    }
}
```

This is mostly useless obviously, so let's move on and define how to parse the operators our calculator can use:

```scala
class ReversePolishCalculator extends JavaTokenParsers {
    def num: Parser[Float] = floatingPointNumber ^^ (_.toFloat)
    def operator: Parser[(Float, Float) => Float] = ("*" | "/" | "+" | "-") ^^ {
        case "+" => (x, y) => x + y
        case "-" => (x, y) => x - y
        case "*" => (x, y) => x * y
        case "/" => (x, y) => if (y > 0) (x / y) else 0.f
    }
}
```

The `operator` parser matches any of the operators listed, in the order they are specified - which is fantastic when you think about it, because we were able to encode the correct order of operations in the very same code which defines the operators themselves! This parser then transforms the operator into a function which maps two floats to a single float - which sounds an awful lot like how you would expect mathematical operations to work (applying an operator, or function, over two operands). We haven't connected the dots just yet, but these two parsers are the cornerstone of the rest we will be adding. The next step is to define the property of Reverse Polish Notation that allows us to have N-many numbers before an operator (ex: `5 1 2 + 4 * 3 -`). The parser for this is simple:

```elixir
class ReversePolishCalculator extends JavaTokenParsers {
    def term: Parser[List[Float]] = rep(num)
    def num: Parser[Float] = floatingPointNumber ^^ (_.toFloat)
    def operator: Parser[(Float, Float) => Float] = ("*" | "/" | "+" | "-") ^^ {
        case "+" => (x, y) => x + y
        case "-" => (x, y) => x - y
        case "*" => (x, y) => x * y
        case "/" => (x, y) => if (y > 0) (x / y) else 0.f
    }
}
```

The `term` function simply states that it will parse N-many floating point values (`rep` stands for repeat), and return a list of floats as a result. We're getting close to our final product here, the final step is to define how to parse mathematical expressions which our calculator can understand:

```scala
class ReversePolishCalculator extends JavaTokenParsers {
    def expr: Parser[Float] = rep(term ~ operator) ^^ {
        // match a list of term~operator
        case terms =>
            // Each operand will be placed on the stack, and pairs will be popped off for each operation,
            // replacing the pair with the result of the operation. Calculation ends when the final operator
            // is applied to all remaining operands
            var stack  = List.empty[Float]
            // Remember the last operation performed, default to addition
            var lastOp: (Float, Float) => Float = (x, y) => x + y
            terms.foreach(t =>
                // match on the operator to perform the appropriate calculation
                t match {
                    // append the operands to the stack, and reduce the pair at the top using the current operator
                    case nums ~ op => lastOp = op; stack = reduce(stack ++ nums, op)
                }
            )
            // Apply the last operation to all remaining operands
            stack.reduceRight((x, y) => lastOp(y, x))
    }
    def term: Parser[List[Float]] = rep(num)
    def num: Parser[Float] = floatingPointNumber ^^ (_.toFloat)
    def operator: Parser[(Float, Float) => Float] = ("*" | "/" | "+" | "-") ^^ {
        case "+" => (x, y) => x + y
        case "-" => (x, y) => x - y
        case "*" => (x, y) => x * y
        case "/" => (x, y) => if (y > 0) (x / y) else 0.f
    }

    // Reduces a stack of numbers by popping the last pair off the stack, applying op, and pushing the result
    def reduce(nums: List[Float], op: (Float, Float) => Float): List[Float] = {
        // Reversing the list lets us use pattern matching to destructure the list safely
        val result = nums.reverse match {
            // Has at least two numbers at the end
            case x :: y :: xs => xs ++ List(op(y, x))
            // List of only one number
            case List(x)      => List(x)
            // Empty list
            case _            => List.empty[Float]
        }
        result
    }
}
```

The comments explain the internals, but from a high level, our `expr` parser states that it expects any number of floating point values (`term`), followed by an operator (`~` says that the left operand must be followed by the right operand in order to match), and that this term-followed-by-operator pair can repeat any number of times. Without the `rep`, an expression could only consist of a set of numbers followed by a single operator - not very useful. With, it allows us to have multiple operations strung together (essentially, the difference between `5 1 2 +` and `5 1 2 + 4 * 3-`). The internals are less important, but in order to fufill the semantics of Reverse Polish Notation, operands are added to a stack as they are encountered, and for each operator encountered, the last two operands are popped off the stack, and replaced with the result of applying the operator. If there are more than two operands remaining when the last operator is encountered, we just apply that operator to each pair of operands until only the final result remains.

If you are new to Scala, the `reduce` helper I added should be rather interesting to you (well, this whole article should..). If you haven't witnessed the power of pattern matching before, this is a prime example of the kind of expressive power it contains. It is very simple and easy to read what we are doing here: reverse the list we are using as a stack, and if it contains two elements (x and y) followed by any number of other elements (xs), apply the operator function to x and y and put it back on the stack. If it's a list of one element, do nothing, and if the stack doesn't match those two states, it must be (or should be) empty. In many other languages, this kind of code would be much messier, and far more error prone.

## The Final Product

The final, executable version of our Reverse Polish Notation calculator would look like the following after refactoring it to be more idiotmatic Scala:

```scala
import scala.util.parsing.combinator._

/**
 * This trait provides the mathematical operations which the calculator can perform.
 */
trait Maths {
  def add(x: Float, y: Float) = x + y
  def sub(x: Float, y: Float) = x - y
  def mul(x: Float, y: Float) = x * y
  def div(x: Float, y: Float) = if (y > 0) (x / y) else 0.0f
}

/**
 * This class is the complete Reverse Polish parser and calculator
 * JavaTokenParsers is extended in order to use the floatingPointNumber parser
 * Maths is extended to provide the underlying mathematical operations
 */
class ReversePolishCalculator extends JavaTokenParsers with Maths {
  /**
   * Takes an expression, which consists of N repetitions of a term followed by an operator
   * In case you are wondering, the parser combinators used here are as follows:
   *  |   => The alternation combinator, it parses successfully if either the left or right side match
   *  ~   => This combinator forms a sequential combination of it's operands (ex. a~b expects a followed by b)
   *  ~>  => This combinator says "ensure the left operand exists, but don't include it in the result"
   *  <~  => This combinator says "ensure the right operand exists, but don't include it in the result"
   *  ^^  => This combinator says "if parsed successfully, transform the result using the block on the right"
   *  rep => This combinator says "expect zero or more repetitions of X"
   */
  def expr:   Parser[Float] = rep(term ~ operator) ^^ {
    // match a list of term~operator
    case terms =>
      // Each operand will be placed on the stack, and pairs will be popped off for each operation,
      // replacing the pair with the result of the operation. Calculation ends when the final operator
      // is applied to all remaining operands
      var stack  = List.empty[Float]
      // Remember the last operation performed, default to addition
      var lastOp: (Float, Float) => Float = add
      terms.foreach(t =>
        // match on the operator to perform the appropriate calculation
        t match {
          // append the operands to the stack, and reduce the pair at the top using the current operator
          case nums ~ op => lastOp = op; stack = reduce(stack ++ nums, op)
        }
      )
      // Apply the last operation to all remaining operands
      stack.reduceRight((x, y) => lastOp(y, x))
  }
  // A term is N factors
  def term: Parser[List[Float]] = rep(factor)
  // A factor is either a number, or another expression (wrapped in parens), converted to Float
  def factor: Parser[Float] = num | "(" ~> expr <~ ")" ^^ (_.toFloat)
  // Converts a floating point number as a String to Float
  def num: Parser[Float] = floatingPointNumber ^^ (_.toFloat)
  // Parses an operator and converts it to the underlying function it logically maps to
  def operator: Parser[(Float, Float) => Float] = ("*" | "/" | "+" | "-") ^^ {
    case "+" => add
    case "-" => sub
    case "*" => mul
    case "/" => div
  }

  // Reduces a stack of numbers by popping the last pair off the stack, applying op, and pushing the result
  def reduce(nums: List[Float], op: (Float, Float) => Float): List[Float] = {
    // Reversing the list lets us use pattern matching to destructure the list safely
    val result = nums.reverse match {
      // Has at least two numbers at the end
      case x :: y :: xs => xs ++ List(op(y, x))
      // List of only one number
      case List(x)      => List(x)
      // Empty list
      case _            => List.empty[Float]
    }
    result
  }
}

object Calculator extends ReversePolishCalculator {
  def main(args: Array[String]) {
    println("input: " + args(0))
    println("result: " + calculate(args(0)))
  }

  // Parse an expression and return the calculated result as a String
  def calculate(expression: String) = parseAll(expr, expression)
}
```

## Wrapping Up

And that's it! An example of applying Scala's parser combinators to an admittedly trivial problem, but it doesn't take much to extend what you've learned here to more practical problems you may be facing every day. Feel free to leave a comment if you have any questions about this article, Scala, or parser combinators!
