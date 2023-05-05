Dart Smalltalk-72
=================

This is an **incomplete** and probably buggy **Dart** port of Dan Ingalls' **Smalltalk-72 simulator** that he wrote in 1999 for Squeak Smalltalk as a birthday present for Alan Kay.

A few of years ago, I started to translate most of Dan's Squeak Smalltalk source code as verbatim as possible to Dart. Now (in 2021) I have updated that incomplete code to sound and null-safe Dart 2.13 (and later to 2.18 and 3.0).

This is the result.

## Quickstart

    dart pub get
    dart run

This will print a bunch of log messages while it tries to run the initialization code, which will eventually simulate turtle graphics. Look for `7` and `3.14159292`, which is the result of the first code run after bootstrapping.

### Running the Code

1. Import `lib/st72.dart`.

2. Call `St72.bootFrom(source)` to bootstrap the system. `source` should be the contents of the `ALLDEFS` file that contains all the Smalltalk-72 source code. I took the liberty of including it here. I hope no one objects.

3. Run `St72.runAsUserText('3+4')` to execute the canonical smoke test. This should print `7` and is almost the only thing I have tried so far. However, I happen to know that Dan and others have always said that this simple looking expression exercises most of the system.

### Modifications

`ALLDEFS` contained some "invisible" characters, that is, characters with ASCII values (or Unicode codepoints) less than 32.

* I made sure that line endings are marked with 13 (CR), not 10 (LF) or both.
* I replaced 3 (open colon) with `⦂` (U+2982).
* I replaced 15, which occurred only inside of string literals (aka comments) with ` as it was used to quote keywords as far as I could tell.
* I removed 17 which occurred only once inside a string literal (aka comment) and served no other purpose.
* I replaced 19 (possessive s) with `❜` (U+275C).

BTW, I noticed that the Smalltalk simulator expects `<=` or `>=` for comparison which will not work because the scanner cannot create multi-character non-alphanumeric atoms. The original Smalltalk-72 used 1 (≤) and 26 (≥) here.

### Implementation Details

The original system was embedded in [Squeak](https://squeak.org/) (which is a dialect of Smalltalk-80 recreated by Alan Kay and Dan Ingalls) and shared some code: Most if not all of the built-in types, and of course the graphics subsystem.

As with the Squeak host, I tried to reuse the built-in Dart types.

I use Dart `int`, `double`, `bool`, and `List` to represent Smalltalk integer objects, floating-point objects, the `false` object, and vectors of objects. I use Dart `String` as the type for atoms a.k.a. symbols. Then, I added an ad-hoc `Str` class to represent Smalltalk strings that are mutable – a fact I once knew but which I forgot over the years. I'm not sure whether mapping `nil` to Dart's `null` was a good idea. Last but not least, I added `StClass` to represent Smalltalk(-80) classes and `StObject` to represent instances of those classes. There's no meta shenanigans, though.

Smalltalk-72 class | Dart equivalent
-------------------|----------------
`number`           | `int`
`vector`           | `List<Object?>`
`atom`             | `String`
`string`           | `Str`
`arec`             | `St72(Context)`
`float`            | `double`
`falseclass`       | `bool`
`class`            | `StClass`
`instance`         | `StObject`

By using Dart's `typedef`, I called "pointers" to objects `OOP` (aliased as `Object?`) and arrays of such "pointers" `StVector` (aliased as `List<Object?>`).

I added my own `scan` function to split a string of source code into tokens using _regular expression magic_ and my own class `InputStream` to access a Dart string like a Smalltalk stream. For the Smalltalk Transcript I use a Dart `StringSink`.

The original code had a `ST72Object` root class that has class methods `classTable` and `classTable:` (backed by class instance variable `table`) so that all user-defined Smalltalk-72 objects, which are instances of _uninterned_ `ST72Thing` classes (that are then renamed to a Smalltalk-72 name), which are in turn subclasses of `ST72Object`, all have such a getter to access the Smalltalk-72 method dictionary. Then, system classes where extended to also have such a getter. I make my own implementation using `StClass` and `StObject` here and added some helper functions.

I tried to convert Smalltalk's 1-based subscripts to _normal_ 0-based subscripts and hopefully, didn't introduce off-by-one errors. If something doesn't work, this might be a source of difficult-to-find bugs!

### Primitives

Smalltak-72 is based on 32 primitive operations.

Names in parentheses aren't implemented in the Squeak simulator. Some of them are handled directly in `eval`, but others (`mem`, `leech`, and `nextp`) seem to be missing – probably because they are very low-level. The second column shows whether I have implemented the primitive or not.

 # | name         | status
---|--------------|---------
 1 | repreat      | done
 2 | read         | done
 3 | strVec       | done
 4 | number       | done
 5 | isnew        | done
 6 | again        | done
 9 | (")          | n/a
10 | apply        | missing
11 | false        | done
12 | put          | done
13 | (!)          | in eval
15 | eq           | done
17 | (%)          | in eval
18 | (:)          | in eval
19 | to           | done
20 | kbd          | partially, requires UI
21 | turtle       | partially, requires UI
22 | stream       | done
23 | disp         | partially, requires UI
24 | for          | done
25 | done         | done
26 | (mem)        | n/a
27 | (leech)      | n/a
28 | get          | done
29 | atom         | done
35 | mouse        | missing, requires UI
36 | (opencolon)  | in eval
40 | substr       | done
42 | float        | done
50 | (nextp)      | n/a
51 | textframe    | missing, requires UI
52 | dclearetc    | missing

"done" means that the primitive is implemented in Dart. "missing" means, it is not implemented yet. Some primitives are implemented only "partially". "requires UI" means that this needs, well, some graphical UI and makes no sense with just a command line. I could imagine a Flutter implemention or a stand-alone version based on [SDL](https://www.libsdl.org/). These should also use the old font file for added flavor.

## Links and References

You probably need more [documentation](http://www.bitsavers.org/pdf/xerox/parc/techReports/Smalltalk-72_Instruction_Manual_Mar76.pdf) to understand [Smalltalk-72](https://wiki.squeak.org/squeak/989) which to modern eyes looks kind of strange – especially because it used some fancy "emojis" as tokens in the documentation. The `ALLDEFS` file uses ASCII equivalents.

Smalltalk-72 was one of the first graphical programming environments, and very influential in our industry. So it's fun to play around with Smalltalk in general and its earliest version in particular.

For me, the fun is implementing such a language. If you just want to use it and try it out, there's an [app](https://lively-web.org/users/Dan/ALTO-Smalltalk-72.html) for that.
