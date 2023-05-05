/// Rosetta Smalltalk in Dart
///
/// This is an attempt to re-implement **Rosetta Smalltalk** from its
/// somewhat incomplete description in the [ACM paper][] from 1979. It is
/// written in Dart (instead of Z80 machine code) and tries in no way to
/// be an efficient implementation.
///
/// [ACM paper]: https://archive.org/details/RosettaSmalltalkACM1979
///
/// All data types in Rosetta Smalltalk (RST) are so called _objects_.
/// Objects belong to _classes_ (which are also objects). Classes define
/// common behavior in form of _methods_ that can be invoked by sending
/// _messages_. Those messages may carry one or more _arguments_ (which
/// are objects, of course). There are five basic types of objects: atoms,
/// numbers, strings, lists, and instances.
///
/// They map to Dart like so:
///
///  - `String` for atoms
///  - `int` for numbers (32+ bits)
///  - `List<int>` for strings (elements are `codeUnits`, not bytes)
///  - `List<Object>` for lists (elements are objects, of course)
///  - `Instance` for instances other than the above
///
/// `nil` is represented as an empty list (`<Object>[]`).
///
/// Two singleton objects `yes` and `no` represent boolean values. However,
/// for conditionals, only the `no` (meaning "false") is relevant, any
/// other object (including `nil`) is considered "truish". Both objects are
/// created during the bootstrap.
///
/// Because classes are istances, there is a class called `Class` which is
/// its own class. This class is created during bootstrap and it becomes
/// the class of all other class objects created.
///
/// RST programs are represented as lists of tokens which are either atoms,
/// numbers, strings or lists of such types. A valid RST program must not
/// contain instances.
///
/// Atoms are either sequences of alphanumeric characters that start with a
/// letter, single non-alphanumeric operator characters like `+ - * / @ ^`
/// or two character operator sequences that start with `<`, `>`, or `=`.
/// Numbers consist of digits, with an optional minus sign. Strings are
/// enclosed in double quotes (and cannot contain a double quote character)
/// and lists are enclosed in round in parentheses. All tokens can be
/// separated by whitespace.
///
/// Programs are executed by evaluating them in some context that provides
/// access to values bound to names, a.k.a. variables. There are temporary
/// variables that exists only while a method is executed. Each such method
/// as a receiver object and that object may have instance variables. All
/// objects have a class and that class may have class variables. Temporary
/// variables, instance variables, and class variables are searched in that
/// order. The topmost context provides global variables (implemented as
/// its temporary variables), which are searched if no other search was
/// successful.
///
/// Programs executed by evaluating tokens sequentially. Each evaluation
/// first computes a receiver object by sending the message `… eval` to the
/// next token not yet evaluated. Then the receiver's class is determined
/// and its method dictionary is searched for a matching message that
/// comprises of zero or more tokens, possible including arguments which
/// are evaluated recursively. If a method is found, its list body is
/// executed by sending `… eval`. The result of the evaluation is the next
/// receiver for which the process repeats until there are no more tokens
/// in the list or if the next token is `.` which resets the evaluation and
/// continues with evaluating the token following the `.` as the next
/// receiver by sending the `… eval` message to that token.
///
/// Two objects modify this process: The `done` object understands two
/// messages "`… with (a)`" and "`…`" (yes, that the empty message) which
/// immediately abort the evalation of the current list and return either
/// the argument `a` or the receiver (`self`). The `reply` object
/// understands the same two messages and not only abort the evaluation of
/// the current list but the evaluation of all lists up to including the
/// currently executed method.
///
/// That describes how lists are evaluated. The empty list evaluates to
/// itself, that is `nil`, though. While a list's result is the evaluation
/// of its last expression, method bodies return `self`, the current
/// receiver, by default. You can assume that method bodies implicitly end
/// with `. reply with self`.
///
/// To evaluate numbers and strings, they are simply returned.
///
/// To evaluate an atom, its bound value is searched first in the current
/// temporary variables, the current instance variables, the current class
/// variables and the global variables. The evaluation of lists has already
/// been described.
///
/// Sending a message to a receiver means to search its class' method
/// dictionary for a matching message pattern and, if found, executing the
/// associated method body as code, using the evaluated pattern parameters
/// as new temporary variables, also adding `self` as a special variable
/// that contains the current receiver.
///
/// Message patterns are lists that consist of either atoms or lists that
/// contains a single atom or a `@` atom followed by another atom, a so
/// called quoted list. Simple atoms must match literaly. Lists represent
/// parameters which are then bound the result result of evaluating the
/// next expression from the token stream or in the case of the quoted
/// lists to the next token unevaluated.
///
/// Pattern must be always sorted descending by length and by literal,
/// quoted and unquoted parameter. This way, ambigious matches can be
/// omitted or at least reduced.
///
/// Methods are system primitives represented by numbers or lists of tokens.
///
/// These methods are built-in:
///
///  - `Number eval`: returns the number
///  - `String eval`: returns the string
///  - `List eval`: perform the code execution as described above
///  - `Atom eval`: perform the variable lookup as described above
///  - `Atom <- (a)`: perform variable assignment
///  - `@` is an instance of `quote` and `quote … (@x)` returns a token
///    unevaluated
///  - `^` is an instance of `reply` and `reply … (x)` stops method
///    execution
///  - `done` is an instance of a class that as an empty method to stop
///    list execution
///  - `if` is an instance of a class that has a `(cond) => (@code)` method
///    to execute `code` only if `cond` evaluates to something other than
///    `no` and then automatically executes `done` to abort the execution
///    of the list that contains the `if`.
///
/// For more methods, and more description, check out the linked paper.
library rst;

// just for documention, all tests must be inlined to utilize local type
// inference; Dart has no type guards like TypeScript does, unfortunately
//
// bool isAtom(Object o) => o is String
// bool isNumber(Object o) => o is int
// bool isString(Object o) => o is List<int>
// bool isList(Object o) => o is List<Object>
// bool isInstance(Object o) => o is Instance

/// Instead of `null`, I will use the empty list as `nil`.
const nil = <Object>[];

/// Tests [o] for being `nil`.
bool isNil(Object o) => o is List<Object> && o.isEmpty;

// it would probably more natural to linked lists instead of `List`;
// to simulate this, I will not use an inplace add but the following
// method even if it is very inefficient
extension LinkedList on List<Object> {
  List<Object> adding(List<Object> list, Object value) => //
      list.isEmpty ? [value] : (list.toList()..add(value));
}

// there is no need for makeAtom, makeInt, or makeList.
//
// String makeAtom(String s) => s;
// int makeInt(int i) => i;
// List<Object> makeList(List<Object> list) => list;

/// Makes a new string from [s].
List<int> makeString(String s) => s.codeUnits;

/// Makes a new dictionary from [bindings] (key-value pairs as 2-element lists).
List<Object> makeDictionary([Iterable<List<Object>> bindings = const []]) {
  assert(bindings.every((binding) => binding.length == 2));
  return bindings.toList();
}

/// Makes a new dictionary from [names], all bound to [nil].
List<Object> makeDictionaryFromNames(Iterable<Object> names) {
  assert(names.every((name) => name is String));
  return makeDictionary(names.map((name) => [name, nil]));
}

extension Dictionary on List<Object> {
  /// Interprets a list as a dictionary and returns its bindings.
  Iterable<List<Object>> get bindings => whereType<List<Object>>();

  /// Returns a binding for [key] if there is one.
  /// A binding is a 2-element list of key and value.
  List<Object>? bindingAt(Object key) {
    for (final binding in bindings) {
      if (binding[0] == key) return binding;
    }
    return null;
  }

  /// Returns the object bound to [key] which must exist.
  Object at(Object key) => bindingAt(key)![1];

  /// Rebinds [key] to [value], [key] must exist.
  void atPut(Object key, Object value) => bindingAt(key)![1] = value;

  /// Binds [key] to [value], [key] must not exist.
  List<Object> binding(Object key, Object value) => adding(this, [key, value]);
}

/// [Instance] represents all objects that aren't basic atoms, numbers,
/// strings or lists and which are instances of classes. Classes are also
/// represented as [Instance] instances of type `Class` which is a
/// singleton class object that is its own class.
///
/// All instances have zero or more instance variables which are stored in
/// dictionaries, which are lists of 2-element-lists of variable names
/// (atoms) and bound values (any object).
///
/// Classes have four instance variables to store their `title`, `methods`,
/// `cvars`, and `ivars`. The title should be a string. The method
/// dictionary is a list of 2-element-lists. The first element is a
/// message pattern, the second element is a method body. The message
/// pattern is a list of atoms or lists with one or two elements, which
/// must be atoms. For the two element list, the first atom must be `@`.
/// The body is either a number of a list of tokens. The class variables
/// `cvars` are organized as dictionary like instance variables. The
/// `ivars` template is a list of instance variable names used to create
/// the `ivars` dictionary of new instances.
///
/// Use [Instance.classClass()] to create the special `Class` object.
class Instance {
  /// Makes a new instance of [iclass] which must be a class object.
  Instance(this.iclass) : ivars = makeDictionaryFromNames(iclass.ivarAt(3));

  /// Makes the special `Class` instance which is its own instance and
  /// initialize its instance variables with the required values to set
  /// up the initial class of which all other classes are instances.
  Instance.classClass() : ivars = makeDictionaryFromNames(_classIvars) {
    iclass = this;
    ivarAtPut(0, 'Class'.codeUnits);
    ivarAtPut(1, makeDictionary());
    ivarAtPut(2, makeDictionary());
    ivarAtPut(3, _classIvars);
  }

  /// The class object.
  late final Instance iclass;

  /// The instance variables dictionary.
  final List<Object> ivars;

  /// Returns the value of the [index]th instance variable, cast to [T].
  T ivarAt<T>(int index) => (ivars[index] as List<Object>)[1] as T;

  /// Sets the [index]th instance variable to [value];
  void ivarAtPut(int index, Object value) {
    (ivars[index] as List<Object>)[1] = value;
  }

  /// Assuming this is a class, return its name.
  String get title => String.fromCharCodes(ivarAt(0));

  /// Assuming this is a class, return its methods dictionary.
  List<Object> get methods => ivarAt(1);

  /// Assuming this is a class, return its variables.
  List<Object> get cvars => ivarAt(2);

  /// Assuming this is a class, add [method] to its methods dictionary
  /// using [pattern] (which must be a list of atoms or lists of atoms)
  /// as the key. If method is an integer, it is a system primitive.
  void addMethod(Object pattern, Object method) {
    final p = pattern as List<Object>;
    assert(
      p.every(
          (p) => p is String || p is List<Object> && (p.length == 1 || p.length == 2) && p.every((e) => e is String)),
      '$p is an invalid message pattern',
    );
    assert(method is int || method is List<Object>);
    ivarAtPut(1, methods.binding(p, method));
  }

  @override
  String toString() => iclass == this ? '<Class>' : '<$iclass instance>';

  /// The ivars template of class objects.
  static const _classIvars = <Object>['title', 'methods', 'cvars', 'ivars'];
}

/// [Context] evaluates Smalltalk code. It has temporary variables.
class Context {
  Context(
    this.code,
    this.tvars,
    this.sender,
    this.outer,
  ) : index = 0;

  /// what to evaluate, see [index]
  List<Object> code;

  /// where is the next token, see [code]
  int index;

  /// context's temporary variables
  List<Object> tvars;

  /// caller if this is a method context
  Context? sender;

  /// outer context if this isn't a method context
  Context? outer;

  /// the global variables
  List<Object> get globals {
    var ctxt = this;
    while (ctxt.sender != null) {
      ctxt = ctxt.sender!;
    }
    return ctxt.tvars;
  }

  /// the current receiver (`self` from the method context)
  Object get receiver {
    final binding = tvars.bindingAt('self');
    return binding != null ? binding[1] : nil;
  }

  /// Evaluates all expression from [code] and returns either the receiver or
  /// the method's reply if this is a method context or the context's done
  /// value.
  Object evalCode() {
    try {
      while (!atEnd) {
        evalNext();
        if (!atEoE) {
          throw 'unexpected token ${peek()}';
        }
        match('.');
      }
      return receiver;
    } on _Done catch (d) {
      return d.value;
    } on _Reply catch (r) {
      if (outer != null) rethrow;
      return r.value;
    }
  }

  /// Returns the next completely evaluated expression.
  Object evalNext() {
    if (atEoE) throw 'expression missing';
    var rcvr = eval();
    while (!atEoE) {
      final old = index;
      rcvr = apply(rcvr);
      if (index == old) break;
    }
    return rcvr;
  }

  /// Evaluates the current token.
  Object eval() {
    final token = peek();
    if (token is String) {
      // atoms are evaluated as bindings with two exceptions: a `@` is
      // shortcutted to return the next token unevaluated, a `^` is
      // shortcutted to reply the result of evaluating the next expression
      index++;
      if (token == '@') {
        if (atEnd) throw 'no token after @';
        return code[index++];
      }
      if (token == '^') {
        if (atEoE) throw _Reply(receiver);
        throw _Reply(evalNext());
      }
      return lookup(token);
    }
    if (token is int || token is List<int>) {
      // numbers and strings evaluate to themselves.
      index++;
      return token;
    }
    if (token is List<Object>) {
      // lists are evaluated as code
      index++;
      // but not nil, which should be simply nil
      if (isNil(token)) return token;
      return Context(token, tvars, null, this).evalCode();
    }
    throw 'code contains unexpected token $token';
  }

  /// Lookup value bound to [token].
  Object lookup(String token) {
    // search temporary variables
    for (Context? ctxt = this; ctxt != null; ctxt = ctxt.outer) {
      final binding = tvars.bindingAt(token);
      if (binding != null) return binding[1];
    }
    // then search instance variables
    final rcvr = receiver;
    if (rcvr is Instance) {
      final binding = rcvr.ivars.bindingAt(token);
      if (binding != null) return binding[1];
    }
    // and then class variables and last but not least global variables
    final clss = classOf(rcvr);
    final binding = clss.cvars.bindingAt(token) ?? globals.bindingAt(token);
    if (binding != null) return binding[1];
    throw 'unbound variable $token';
  }

  /// Evaluates the next expression, then assigns that value to [token] or
  /// creates a new temporary variables binding for [token] if there is none.
  Object assign(String token) {
    final value = evalNext();
    // search temporary variables
    for (Context? ctxt = this; ctxt != null; ctxt = ctxt.outer) {
      final binding = tvars.bindingAt(token);
      if (binding != null) return binding[1] = value;
    }
    // then search instance variables
    final rcvr = receiver;
    if (rcvr is Instance) {
      final binding = rcvr.ivars.bindingAt(token);
      if (binding != null) return binding[1] = value;
    }
    // and then class variables
    final clss = classOf(rcvr);
    final binding = clss.cvars.bindingAt(token) ?? globals.bindingAt(token);
    if (binding != null) return binding[1] = value;
    // if there is no binding yet, make one
    tvars = tvars.binding(token, value);
    return value;
  }

  /// Sends a single message to [rcvr].
  Object apply(Object rcvr) {
    // shortcut for sending `... <- (a)` to atoms
    if (match('<-') && rcvr is String) return assign(rcvr);
    // shortcut for sending `... eval`
    if (match('eval')) {
      if (rcvr is String) return lookup(rcvr);
      if (rcvr is List<Object>) return Context(rcvr, tvars, sender, this).evalCode();
      if (rcvr is int || rcvr is List<int>) return rcvr;
    }
    // search for method in o's class
    final clss = classOf(rcvr);
    // to store matched expressions
    var vars = makeDictionary();
    // we might need to reset the token stream because of failed matches
    // this cannot be the right way to do it, though, because we could
    // accidentally evaluate the tokens multiple times and that could
    // lead to unwanted side effects – but I have no idea how to do it
    // differently
    final reset = index;
    // it is very important that the primitive to add new methods to a
    // class sorts the bindings by longest match and by prefering a literal
    // match before an unevaluated match before an evaluated match
    outer:
    for (final binding in clss.methods.bindings) {
      final pattern = binding[0] as List<Object>;
      // always reset tokens to the beginning
      index = reset;
      for (final p in pattern) {
        if (atEoE) {
          // not enough tokens left, pattern cannot match
          // so we must continue with the next pattern
          continue outer;
        }
        if (p is List<Object>) {
          // if (vars.isNotEmpty) throw 'try to re-evaluating arguments';
          if (p.length == 2) {
            // (@var) match
            vars = vars.binding(p[1], peek());
            index++;
          } else {
            // (var) match
            vars = vars.binding(p[0], evalNext());
          }
          continue;
        } else if (peek() == p) {
          // literal match
          index++;
          continue;
        }
        continue outer;
      }
      return send(binding[1], rcvr, vars);
    }
    // no method found, which isn't a problem pe se
    if (vars.isNotEmpty) throw 'half-evaluated arguments';
    index = reset;
    return rcvr;
  }

  /// Evaluates [method] sent to [rcvr] with temporary variables [vars].
  Object send(Object method, Object rcvr, List<Object> vars) {
    if (method is int) {
      switch (method) {
        case 1: // answer (pattern) by (method)
          (rcvr as Instance).addMethod(vars.at('pattern'), vars.at('method'));
          return rcvr;
        case 2: // new
          return doIsnew(Instance((rcvr as Instance)));
        case 3: // is?
          return classOf(rcvr);
        case 4: // eq
          return vars.at('a') == vars.at('b') ? yes : no;
        case 5: // =>
          if (vars.at('cond') == no) return rcvr;
          throw _Done(Context(vars.add('code') as List<Object>, tvars, null, this).evalCode());
        case 6: // +
          return (rcvr as int) + (vars.at('other') as int);
        case 7: // -
          return (rcvr as int) - (vars.at('other') as int);
        default:
          throw 'unknown primitive $method';
      }
    }
    return Context(
      method as List<Object>,
      vars.binding('self', rcvr),
      this,
      null,
    ).evalCode();
  }

  Object doIsnew(Instance inst) {
    var vars = makeDictionary();
    final reset = index;
    outer:
    for (final binding in inst.iclass.methods.bindings) {
      final pattern = binding[0] as List<Object>;
      if (pattern.isNotEmpty && pattern.first == 'isnew') {
        index = reset;
        for (final p in pattern.skip(1)) {
          if (atEnd || peek() == '.') continue outer;
          if (p is List<Object>) {
            if (vars.isNotEmpty) throw 'try to re-evaluating arguments';
            if (p.length == 2) {
              vars = vars.binding(p[1], peek());
              index++;
            } else {
              vars = vars.binding(p[0], evalNext());
            }
          } else {
            if (p != peek()) continue outer;
          }
        }
        // we matched an `isnew ...` pattern
        send(binding[1], inst, tvars);
        return inst;
      }
    }
    // we didn't find an `isnew ...` pattern, which is okay
    // unfortunately, we reach this also for half-matches
    // which is not okay and needs to be fixed later
    if (vars.isNotEmpty) throw 'half-evaluated arguments';
    index = reset;
    return inst;
  }

  // ---- utilities ----

  /// Returns true if there are no more tokens in [code].
  bool get atEnd => index >= code.length;

  /// Returns the next token from [code] without consuming it.
  Object peek() => atEnd ? nil : code[index];

  /// Tries to match atom [a].
  bool match(String a) {
    if (peek() == a) {
      index++;
      return true;
    }
    return false;
  }

  /// Tests for end of expression.
  bool get atEoE => atEnd || peek() == '.';
}

/// Signals an early return from a method, see [Context.evalCode].
class _Reply implements Exception {
  _Reply(this.value);

  final Object value;
}

/// Signals an early return from a method, see [Context.evalCode].
class _Done implements Exception {
  _Done(this.value);

  final Object value;
}

/// Returns the class object for [o].
Instance classOf(Object o) {
  if (o is String) return atomClass;
  if (o is int) return numberClass;
  if (o is List<int>) return stringClass;
  if (o is List<Object>) return listClass;
  if (o is Instance) return o.iclass;
  throw Exception('invalid object $o');
}

/// Parses [input] into a list of tokens.
///
/// Tokens are either atoms, numbers, strings or lists of tokens.
/// Whitespace is ignored, as are line comments starting with `!!`.
///
/// EBNF grammar:
///
/// ```ebnf
/// expr = atom | number | string | list.
/// atom = name | operator.
/// name = letter {letter | digit}.
/// operator = /[<=>][-<=>]?|[-+*/&|?@^.]|'s/
/// number = ["-"] digit {digit}.
/// letter = /[a-zA-Z]/.
/// digit = /[0-9]/.
/// string = /"[^"]*"/.
/// list = "(" {expr} ")".
/// ```
///
/// Throws a [FormatException] on invalid numbers or unknown characters.
List<Object> read(String input) {
  final stack = <List<Object>>[[]];
  for (final match in _tokens.allMatches(input)) {
    if (match[0] == '(') {
      stack.add([]);
    } else if (match[0] == ')') {
      final value = stack.removeLast();
      stack.last.add(value);
    } else if (match[1] != null) {
      stack.last.add(int.parse(match[1]!));
    } else if (match[2] != null) {
      stack.last.add(match[2]!.codeUnits);
    } else if (match[3] != null) {
      stack.last.add(match[3]!);
    } else if (match[4] != null) {
      throw FormatException('invalid character ${match[4]}');
    }
  }
  return stack.single;
}

final _tokens = RegExp(
  r'\s+|' //          whitespace
  r'!![^\n]*\n?|' //  line comment
  r'[()]|' //         parentheses for lists
  r'(-?\d+)|' //      numbers (group 1)
  r'"(.*?)"|' //      strings (group 2)
  r"(\w+\??|[<>=][-<=>]?|[-+*/&|?@^.←↑]|'s)|" // atoms (group 3)
  r'(.)', //          any other character (group 4)
  dotAll: true,
);

/// Returns a string representation of [o].
String stringify(Object o) {
  if (o is String) return o;
  if (o is int) return '$o';
  if (o is List<int>) return '"${String.fromCharCodes(o)}"';
  if (o is List<Object>) return '(${o.map(stringify).join(' ')})';
  if (o is Instance) return o.toString();
  throw 'cannot stringify $o';
}

/// Bootstraps the system.
void bootstrap() {
  final classClass = Instance.classClass();
  classClass.addMethod(read('answer (pattern) by (method)'), 1);

  atomClass = Instance(classClass);
  numberClass = Instance(classClass);
  stringClass = Instance(classClass);
  listClass = Instance(classClass);
  no = Instance(Instance(classClass));
  yes = Instance(Instance(classClass));

  final pattern = <Object>['is?'];
  atomClass.addMethod(pattern, 3);
  numberClass.addMethod(pattern, 3);
  stringClass.addMethod(pattern, 3);
  listClass.addMethod(pattern, 3);

  final code = '''
    !! We start with `Class` bound in the current context.
    !! That class has one predefined method to add more methods.
    !!
    !! Class answer @(answer (pattern) by (method)) by 1.

    !! We can use that method to add `new` to create new instances.
    Class answer @(new) by 2.
    Class answer @(is?) by 3.

    !! `new` creates an object that knows the receiver as class and has
    !! empty `ivars` created from the receiver's `ivars` template list
    !! after which `new` automatically invokes a message pattern starting
    !! with `isnew`. For classes this should set up the method dictionary
    !! (knowing its internal representation) with `new` so that you can
    !! create instances by those newly created class objects and `is?` to
    !! ask those instances for their class. It also initializes the class
    !! variables and makes sure that new classes have the four given
    !! instance variables.
    Class answer @(isnew) by @(
      @methods <- @(
        ((new) 2)
        ((is?) 3)
      ).
      @cvars <- @().
      @ivars <- @(title methods cvars ivars).
    ).
    
    !! Setup classes for basic types.
    !!
    !! TODO …explain…
    @Atom <- @a is?.
    @Number <- 0 is?.
    @String <- "" is?.
    @List <- () is?.

    !! TODO …explain…
    Class answer @('s (@code)) by @(code eval).

    !! Let's tell all classes their names.
    Class's (@title <- "Class").
    Atom's (@title <- "Atom").
    Number's (@title <- "Number").
    String's (@title <- "String").
    List's (@title <- "List").

    !! For `if`, we need to represent boolean values. The `no` objects
    !! means "false" and is as special as the class names above. We make a
    !! new (anonymous) class and immediately create a singleton of that
    !! class and call that `no`. Note that everything but `no` will be
    !! considered "true", not only the `yes` object we will create in just
    !! a moment.
    @no <- Class new new.
    no is? 's (@title <- "Bool").
    @yes <- no is? new.

    !! Now create a class and a singleton of that class which compares two
    !! objects for identity and which returns either `no` or `yes` as result.
    @eq <- Class new.
    eq's (@title <- "equal").
    eq answer @((a) (b)) by 4.
    @eq <- eq new.

    !! Sometimes, people want to say `nil`.
    @nil <- ().

    !! Another important singleon is `if`. It takes a condition and a
    !! code block and evaluates the code block only if the condition is
    !! true.
    @if <- Class new.
    if's (@title <- "if").
    if answer @((cond) => (@code)) by 5.
    @if <- if new.

    !! For completeness, we could define the built-in operations.

    !! `@` as a global called `quote` that will not evaluate its argument.
    @quote <- Class new.
    quote's (@title <- "quote").
    quote answer @((@x)) by @(^ x).
    quote answer @() by @(^ self).
    @@ <- quote new.

    !! This introduces another built-in `^` which is a global called `reply`
    !! which will evaluate its arguments and return it to the sender of the
    !! current method. This can only be expressed by a system primitive
    !! without access to a context.
    @reply <- Class new.
    reply's (@title <- "reply").
    reply answer @((x)) by 99.
    @^ <- reply new.

    !! `<-` is a method of atom which implements binding values. This can
    !! only be expressed by a system primitive without access to a context.
    Atom answer @(<- (x)) by 99.

    !! The system starts evaluation by sending `eval` to the first token.
    !! Let's define `eval` for all kinds of objects, starting with atoms.
    !! Note that the "pseudo primitive" 99 means, we cannot actually
    !! implement this here without access to a context.

    !! Atoms evaluate by looking up their value in the current context.
    Atom answer @(eval) by 99.

    !! Numbers and strings return themselves, expressed by `self` which is
    !! always bound to the receiver.
    Number answer @(eval) by @(^ self).
    String answer @(eval) by @(^ self).

    !! Lists evaluate by executing their tokens sequentially and then
    !! returning the value of the last expression. An empty list, which is
    !! also called `nil` evaluates to itself. Note that the `.` is syntax
    !! and makes sure that an intermediate result is dropped.
    List answer @(eval) by 99.

    !! --------------------------------------------------------------------

    Class answer @(title) by @(^ title).
    Class answer @(methods) by @(^ methods).

    !! Implement arthmetic operations for numbers.
    Number answer @(+ (other)) by 6.
    Number answer @(- (other)) by 7.
    ''';

  globals = (Context(
    read(code),
    makeDictionary().binding('Class', classClass),
    null,
    null,
  )..evalCode())
      .tvars;

  // atomClass = globals.at('Atom') as Instance;
  // numberClass = globals.at('Number') as Instance;
  // stringClass = globals.at('String') as Instance;
  // listClass = globals.at('List') as Instance;
  // no = globals.at('no') as Instance;
  // yes = globals.at('yes') as Instance;
}

// these variables are set in [bootstrap]:

late List<Object> globals;
late Instance atomClass;
late Instance numberClass;
late Instance stringClass;
late Instance listClass;
late Object no;
late Object yes;

/// Reads [input], evaluates it and prints the result.
void evalAndPrint(String input) {
  print(stringify(Context(read(input), globals, null, null).evalNext()));
}

void main() {
  bootstrap();
  evalAndPrint('3 + 4 - 1');
}
