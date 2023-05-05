/*
 xxxx1  number (2 aligned)
 xxx00  list (4 aligned) or instance
  - nil: everything 0
  - list: cdr is also list
  - inst: cdr is number (class?)
 xx010  atom (8 aligned) 13-bit size, class, xx, xx
 xx110  string (8 aligned) 13-bit size, class, xx, xx

*/


# Rosetta Smalltalk

I recently learned that an 8-bit Smalltalk called "Rosetta Smalltalk" for CP/M computers almost saw the light of day. Unfortunately, the 1979 prototype never made it into a commercial application and is probably lost to history. It seems, only an [ACM report](https://archive.org/details/RosettaSmalltalkACM1979) has survived.

RST is very similar to ST-72, but it uses only ASCII characters and was made for running on a text terminal. It also had a somewhat simpler evaluation strategy – I think.

Unfortunately, the report doesn't give me enough information to understand how the message resolution worked. Beacause I'd love to reimplement it. But I can try.

## Data Types

There are five basic types of values: 1) atoms, 2) numbers, 3) strings, 4) objects and 5) lists of such values.

My guess is that classes and methods are represented as objects, as are `yes` and `no` (as the Booleans are called in RST). And if there's a `nil`, it might actually be the empty list.

Because RST (like ST-72) is very Lisp-like, list objects might actually be linked lists of cons cells and `nil` would be a null reference then. I don't know.

* Atoms are represented by strings of letters followed by more letters and digits or by a `<` or `>` optionally followed by another operator symbol or a single operator symbol from a yet-to-be-determined set of operators, which includes a `@`.

* Numbers are 2-complement 14-bit integers and are therefore represented by strings of digits, optionally prefixed by a `-`.

* Strings are enclosed in double quotes and the report doesn't mention any escaping mechanism for including a `"` within a string. Perhaps the `"` can be doubled as with later Smalltalk systems?

* Objects have no literal form.

* Lists are are enclosed in `( )` and can contain space-separated atoms, numbers, strings, or lists.

## Objects

All objects are instances of classes. Classes are also objects. There is a class object called `Class` which is its own instance.

Objects also have instance variables, but this is where things get confusing. Are they addressed by name or by index? Does a class know the names of these variables?

Classes also have class variables. Since there's only one common meta class, that class cannot know the names of class variables, so those variables are probably organized like in a dictionary. Since there's no such type, I assume its a linear list of tuples of names (atoms) and values. This would be a Lisp-style environment and a good fit if lists are actually chained cons cells. Let's call such a structure a dictionary anyway.

If classes store their variables in a dictionary, objects should store their variables in a similar way, I think. Even if it's a bit inefficient.

Furthermore, since there are context objects that provide an evaluation context, and those context objects store temporary variables, they should also use such a dictionary.

So an object (a.k.a. instance) refers to its class and its dictionary.

A class then has instance variables that contain its name (called title), its variable dictionary, and its method dictionary.

## Methods

Methods are described by a _message pattern_ and a _method body_, both of which are lists. 

* The pattern is a possibly empty list of atoms or lists of atoms. That embedded lists contain either a single atom or a `@` and another atom.

* The report also hints that the body might not always be a list but can also be an integer in which case that method would be implemented by a system primitive.

Method resolution works by looking at the _stream_ of tokens after the receiver was successfully evaluated and its class can be determined by the system.

To find the method, all patterns stored in the method dictionary of that class are matched against that input stream. 

* Atom must be matched literaly.
* A list with a single atom is a variable name to which the next experession evaluated from the stream at that position is bound. 
* A list with a `@` is also a variable name but here, the next unevaluated token is bound.

The paper also mentioned that patterns are matched by trying the longest pattern first. But I do not understand how the system prevents speculative evaluation. Let's take these two patterns as an example:

    ... foo (a) bar
    ... foo (@a) baz

If the next token is `foo`, I have to evaluate an expression of arbitrary complexity just to check for `bar` in the token stream. Only if there is no `bar`, I can proceed and perhaps shouldn't have evaluated it at all.

Is it enough first sort everything first by length of pattern and then by `atom` < `(@name)` < `(name)` and then try them in that order?

But what if no pattern matches at all and I have already evalatued stuff that probably should have been evaluated. It could have side effects!

Is the developer supposed to make all methods distinguishable in LL(0)?

## Evaluation

Evaluation happens using a _context_ object.

I think, we can assume that anything to be evaluated is always a list. Therefore, a context should know that list and an index into that list (or if using cons cells, a reference to the first cell) for backtracking purposes.

Here are the rules, infered from the paper:

* Numbers and strings are evaluated to themselves.
* Atoms are evaluated as bindings:
    * We first look for a temporary variable and return the bound object if there is one.
    * Then we search the receiver for an instance variable and return the bound object if there is one.
    * Then we look in the receiver's class for a class variable and return the bound object if there is one.
    * We search the global dictionary for global bindings, such as `@` which is an instance of some `quote` class that has a method with a `...(@x)` pattern and a method body `(^x)` to return the next token unevaluated.
    * We need to somehow continue searching in the outer context, probably right after searching temporary variables and before searching the instance, but not beyond the current method context, so we need two kinds of contexts, let's call them inner and outer contexts.
* Lists are evaluated recursively in an inner context.

Once we have an object, this becomes the current receiver and if the current context's stream is not empty and if the next token isn't a "`.`", we start method resolution again.

The class of the receiver is determined and the sorted list of patterns is matched against the context like this:

* If the pattern contains an atom and the next token is the same atom, consume it and continue matching. Otherwise, abort matching and reset the stream. Fail if the "did eval" flag was set.
* If the pattern contains a list that starts with `@` and the next token exists and isn't "`.`", bind the pattern's variable name to the next token and consume it and continue matching. Otherwise, abort matching the stream. Fail if the "did eval" flag was set.
* If the pattern contains a list (not starting with `@`), recursively evaluate the next expression from the stream, bind the result to the pattern's variable and set the "did eval" flag. The evaluation of the expression should have consumed all tokens. Therefore, continue matching. Otherwise abort matching and reset the stream. Fail if the "did eval" flag was set.
* If we have reached the end of the pattern, pick this method and evaluate it in a context with the bound variables.
* Otherwise continue with the next pattern.
* If there are no more patterns, fail.

There are two special methods that manipulate evaluation, bound to the `reply` and the `done` classes. The former will return a a result to the previous context, aborting the evaluation of the current context and all inner contexts. The latter will break out of a loop.

Here is its definition:

    @done <- Class new new
    done class answer @(with (n)) by 3
    done class answer @() by @(self with nil)

Example:

    for i ← 1 to 10 do (i print. if i = 5 => (done))

## Bootstrap

Let's try to bootstrap the system with the minimal setup possible and then incrementally add more functionality by defining as much as possible in RST.

To do this:

    @Atom <- Class new

We'd need a binding of `@` and `Class`, need the `quote` class as an instance of `Class`, therefore need `Class` object itself, and would need the `… new` method of that class and a `… <- (value)` method of the atom class and hence, that class object as another instance of `Class`.

Let's say we hardcode the behavior of `@`, `<-`, and even `new`. Then all we'd need is a global binding of `Class` containing a class object which is an instance of itself.

However, the runtime should not only know the global bindings, but probably also the classes of the base types (atom, number, string, and list), so that it doesn't have to look them up in the global environment. Or is this acceptable, albeit very slow, behavior?

I think, `Class` needs to understand `answer (pattern) by (method)`, otherwise we cannot define new methods. Let allow `method` being a number for defining system primitives.

Take this:

    Class answer @(is?) by 1

That could then define a `is?` method to determine the class of an object. As mentioned above, the runtime system would have to know the correct names for the classes of the basic types. That feels wrong. Perhaps those classes are well known – but empty and the bootstrap is supposed to name them?

That's better:

    @Atom <- @@ is?
    @Number <- 1 is?
    @String <- "" is?
    @List <- () is?

 The runtime system also needs to know the booleans, I think, because it would again very inefficient to look them up by name. We're then giving names to them during bootstrap, if we have a primitive comparison method `eq`:

    @eq <- Class new new
    @eq is? answer @((a) (b)) by 2
    @yes <- eq 1 1
    @no <- eq 1 0

(Here my thoughts diverge …)
