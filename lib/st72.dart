import 'dart:math';

/// The common type of all Smalltalk objects.
typedef OOP = Object?;

/// The type for arrays of Smalltalk objects.
typedef StVector = List<OOP>;

/// The type for dictionaries mapping symbols to other objects.
typedef StDictionary = Map<String, OOP>;

/// Smalltalk's `nil` so that we don't have to use `null`.
const OOP nil = null;

/// Evaluation mode, see [St72.mode].
enum Mode { eval, ret, apply, repeat }

// some constants for special atom not representable in ASCII
const OpenColon = '\u2982';
const Posessive = '\u275C';

// a.k.a. `ST72Context`
class St72 {
  St72({
    required this.instance,
    required this.clss,
    required this.ret,
    required this.message,
    required this.global,
    required this.temps,
    required this.code,
    required this.subEval,
  })  : pc = 0,
        mode = Mode.eval;

  OOP instance;
  final OOP clss;
  final St72? ret;
  St72? message;
  St72? global;
  final StVector temps;
  int pc;
  StVector code;
  Mode mode;
  OOP value;
  final bool subEval;

  static final TopLev = <String, OOP>{};

  // ---- printing ----

  @override
  String toString() {
    return '$clss ${'$mode'.substring(5)}: ${[
      for (var i = 0; i < code.length; i++) '${i == pc - 1 ? '→' : ''}${code[i] is List ? '(...)' : '${code[i]}'}',
    ].join(' ')}';
  }

  String printStack() {
    final cs = <St72>[];
    for (St72? c = this; c != null; c = c.ret) {
      cs.add(c);
    }
    return cs
        .map((c) => 'arec${cs.indexOf(c) + 1}: $c\n'
            '\tretn=arec${c.ret != null ? cs.indexOf(c.ret!) + 1 : 0}\n'
            '\tmess=arec${c.message != null ? cs.indexOf(c.message!) + 1 : 0}\n'
            '\tglob=arec${c.global != null ? cs.indexOf(c.global!) + 1 : 0}')
        .join('\n');
  }

  // ---- eval ----

  /// Apply the current value to remaining stream.
  void apply() {
    if (value == null) {
      mode = Mode.eval;
      return;
    }
    final token = peekToken();
    if (token == null || token == '.') {
      mode = Mode.eval;
      return;
    }
    if (token == '?') {
      if (value == false) {
        nextToken();
        conditional(false);
        return;
      }
    }
    if (token == 'is') {
      nextToken();
      final title = getClassTable(classOf(value))['TITLE'];
      value = nextToken() == title;
      return;
    }
    value = activate(value);
  }

  void applyValue(OOP value) {
    this.value = value;
    if (mode != Mode.ret) {
      mode = Mode.apply;
    }
  }

  void conditional(bool value) {
    final subVector = nextToken();
    if (!value) {
      mode = Mode.eval;
      return;
    }
    if (subVector is! StVector) throw 'error';
    returnValue(
      St72(
        instance: instance,
        clss: clss,
        ret: this,
        message: message,
        global: global,
        temps: temps,
        code: subVector,
        subEval: subEval,
      ).evaluate(),
    );
  }

  void eval() {
    final token = nextToken();
    if (token == null) {
      returnValue(instance);
    } else if (token == 'CODE') {
      primitive(nextToken() as int);
    } else if (token == '%') {
      applyValue(matchNextFrom(message!));
    } else if (token == ':') {
      fetchFromMsgInContext(message!, message!);
    } else if (token == '?') {
      conditional(true);
    } else if (token == '.') {
    } else if (token == '!') {
      returnValueTo(fetchFrom(this), message!);
    } else if (token == '"') {
      applyValue(nextToken());
    } else if (token == OpenColon) {
      applyValue(message!.nextToken());
    } else if (token == '#') {
      value = valueAt(nextToken() as String);
    } else {
      if (isAtom(token)) {
        value = valueAt(token as String);
        if (value == null) {
          throw '$token has no value.';
        }
      } else {
        value = token;
      }
      applyValue(activate(value));
    }
  }

  OOP evalOnce() {
    mode = Mode.eval;
    eval(); // eval once
    var applyPC = 0;
    while (mode == Mode.apply && pc > applyPC && pc < code.length) {
      applyPC = pc; // keep applying until return or no progress
      apply();
    }
    return value;
  }

  OOP evaluate() {
    mode = Mode.eval;
    if (peekToken() == '.') nextToken();
    while (!(mode == Mode.ret || pc >= code.length)) {
      evalOnce();
    }
    if (mode == Mode.ret) return value;
    if (subEval) {
      if (pc < code.length) mode = Mode.apply;
      return value;
    }
    if (instance != null) return instance;
    return value;
  }

  void reset() {
    pc = 0;
  }

  // ---- activation ----

  OOP activate(OOP classOrInst) {
    if (classOrInst == true || classOrInst is St72) {
      // currently no ST72 semantics
      return classOrInst;
    }
    OOP inst, clss;
    if (isClass(classOrInst)) {
      inst = null;
      clss = classOrInst;
    } else {
      inst = classOrInst;
      clss = classOf(classOrInst);
    }
    return St72(
      instance: inst,
      clss: clss,
      ret: this,
      message: this,
      global: this,
      temps: List<OOP>.filled(getClassTable(clss)['ARSIZE'] as int, null),
      code: getClassTable(clss)['DO'] as StVector,
      subEval: false,
    ).evaluate();
  }

  void returnValue(OOP value) {
    this.value = value;
    if (value == false) {
      final msg = message;
      if (msg != null) {
        if (msg.peekToken() == '?') {
          msg.nextToken();
          msg.nextToken();
        }
      }
    }
    mode = Mode.ret;
  }

  /// Climb the stack, setting return flags along the way.
  void returnValueTo(OOP value, St72 context) {
    for (var caller = this; caller != context; caller = caller.ret!) {
      caller.returnValue(value);
    }
    context.applyValue(value);
  }

  // ---- messages ----

  OOP fetchFrom(St72 context) {
    if (context.peekToken() == '.') return null;
    return context.evalOnce();
  }

  OOP fetchFromMsgInContext(St72 msg, St72 glob) {
    final token = peekToken();
    if (token == '"') {
      nextToken();
      bind(msg.nextToken());
    } else if (token == '#') {
      nextToken();
      final token = msg.nextToken();
      bind(isAtom(token) ? msg.valueAt(token as String) : token);
    } else {
      msg.evalOnce();
      applyValue(bind(msg.value));
    }
  }

  /// Repeats an acknowleged crock in the original ST72 intepreter:
  ///	Test if an inlined vector should be evalled if it is the same
  ///	as the last message token and that is not preceded by a quote(!)
  bool implicitEval(StVector vec) {
    return code[pc - 1] == vec && (pc == 1 || code[pc - 1 - 1] != '"');
  }

  /// Peek ahead in the message stream. If the next token matches this one,
  /// then advance the message stream and return the token.
  /// If not, then do not advance the message, and return false.
  bool matchTokenFrom(OOP token, St72 msg) {
    if (msg.peekToken() == token) {
      msg.nextToken();
      return true;
    }
    return false;
  }

  /// The next token in the code stream is an atom to be matched.
  /// Peek ahead in the message stream. If the next token matches this one,
  /// then advance the message stream and return the token.
  /// If not, then do not advance the message, and return false.
  bool matchNextFrom(St72 msg) {
    return matchTokenFrom(nextToken(), msg);
  }

  OOP nextToken() {
    if (pc == code.length) return null;
    return code[++pc - 1];
  }

  OOP peekToken() {
    if (pc == code.length) return null;
    return code[pc + 1 - 1];
  }

  // ---- lookup ----

  /// Look ahead and if the next token is an atom,
  /// then store [value] as the value of that variable.
  OOP bind(OOP value) {
    this.value = value;
    final token = peekToken();
    if (token == null) return value;
    if (token == '.') return value;
    if (!isAtom(token)) throw 'error';
    nextToken();
    valueAtPut(token as String, value);
    return value;
  }

  /// Tolerates code written in no context, defaulting to the top-level dictionary.
  OOP bootValueAt(String token) {
    if (clss == null) {
      return TopLev[token];
    }
    return valueAt(token);
  }

  /// Tolerates code written in no context, defaulting to the top-level dictionary.
  void bootValueAtPut(String token, OOP value) {
    if (clss == null) {
      TopLev[token] = value;
      return;
    }
    valueAtPut(token, value);
  }

  /// Look up and return the value of this variable. If the variable does not exist at this level, then resend to global.
  OOP valueAt(String token) {
    if (token == 'SELF') return instance;
    if (token == 'MESS') return message;
    if (token == 'GLOB') return global;
    final val = getClassTable(clss)[token];
    if (val == null) {
      return global?.valueAt(token);
    }
    if (val is St72Accessor) {
      return val.getValueForTempsOrInstance(temps, instance);
    }
    return val;
  }

  /// Look up this variable and store aValue as its new value. If the variable does not exist at this level, then resend to global.
  void valueAtPut(String token, OOP value) {
    if (token == 'MESS') {
      message = value as St72;
      return;
    }
    if (token == 'GLOB') {
      global = value as St72;
      return;
    }
    final val = getClassTable(clss)[token];
    if (val == null) {
      if (global == null) {
        getClassTable(clss)[token] = value;
        return;
      }
      global!.valueAtPut(token, value);
      return;
    }
    if (val is St72Accessor) {
      val.putValueIntoTempsOrInstance(value, temps, instance);
      return;
    }
    getClassTable(clss)[token] = value;
  }

  // ---- code primitives ----

  /// Implements again, the loop restart primitive. (CODE 6)
  void codeAgain() {
    for (var caller = this; caller.mode != Mode.repeat; caller = caller.ret!) {
      caller.mode = Mode.ret;
    }
    returnValue(null);
  }

  /// Applies temp1 to caller's message or a vector in temp2. (CODE 10)
  void codeApply() {
    St72 msg;
    if (temps[1] == null) {
      msg = message!;
    } else {
      code = temps[1] as StVector;
      pc = 0;
      msg = this;
    }
    final clssOrInst = temps[0];
    OOP inst, clss;
    if (isClass(clssOrInst)) {
      inst = null;
      clss = clssOrInst;
    } else {
      inst = clssOrInst;
      clss = classOf(inst);
    }
    returnValue(St72(
      instance: inst,
      clss: clss,
      ret: this,
      message: msg.message,
      global: message,
      temps: List<OOP>.filled(getClassTable(clss)['ARSIZE'] as int, null),
      code: getClassTable(clss)['DO'] as StVector,
      subEval: false,
    ).evaluate());
  }

  // Implements primitive operations of atoms. (CODE 29)
  void codeAtom() {
    final msg = message!;
    final token = msg.peekToken();
    if (token == null) return returnValue(instance);
    if (token == '_') {
      msg.nextToken();
      value = fetchFrom(msg);
      global!.valueAtPut(instance as String, value);
      return returnValue(value);
    }
    if (token == 'eval') {
      msg.nextToken();
      return returnValue(msg.valueAt(instance as String));
    }
    if (token == '=') {
      msg.nextToken();
      return returnValue(instance == fetchFrom(msg));
    }
    if (token == 'chars') {
      msg.nextToken();
      return returnValue(Str(instance as String));
    }
  }

  void codeDClearEtc() => throw UnimplementedError();

  /// Implements output to a character display. (CODE 23)
  void codeDisp() {
    final ch = temps[0] as int;
    transcript.writeCharCode(ch == 13 ? 10 : ch);
    returnValue(ch);
  }

  /// Implements done, the loop termination primitive. (CODE 25)
  void codeDone() {
    var caller = this;
    while (caller.mode != Mode.repeat) {
      caller.returnValue(null);
      caller = caller.ret!;
    }
    caller.returnValue(temps[0]);
    returnValue(null);
  }

  /// Implements test for two identical object. (CODE 15)
  void codeEq() {
    returnValue(fetch() == fetch());
  }

  /// Implements primitive operations of false. (CODE 11)
  void codeFalse() {
    final msg = message!;
    final token = msg.peekToken();
    if (token == null) return returnValue(instance);
    if (token == 'or') {
      msg.nextToken();
      return returnValue(fetchFrom(msg));
    }
    if (token == 'and' || token == '<' || token == '=' || token == '>') {
      msg.nextToken();
      fetchFrom(msg);
      return returnValue(instance);
    }
  }

  /// Implements primitive operations of floating-point numbers. (CODE 42)
  void codeFloat() {
    final msg = message!;
    final token = msg.peekToken();
    if (token == null) return returnValue(instance);
    // Arithmetic ops, +, -, etc.
    if (token == '+') return advanceAndApply((a, b) => a + b);
    if (token == '-') return advanceAndApply((a, b) => a - b);
    if (token == '*') return advanceAndApply((a, b) => a * b);
    if (token == '/') return advanceAndApply((a, b) => a / b);
    if (token == '<') return advanceAndCompare((a, b) => a < b);
    if (token == '=') return advanceAndCompare((a, b) => a == b);
    if (token == '>') return advanceAndCompare((a, b) => a > b);
    if (token == '<=') return advanceAndCompare((a, b) => a <= b);
    if (token == '#') return advanceAndCompare((a, b) => a != b);
    if (token == '>=') return advanceAndCompare((a, b) => a >= b);
    if (token == 'ipart') {
      msg.nextToken();
      return returnValue((instance as double).floor());
    }
    if (token == 'fpart') {
      msg.nextToken();
      return returnValue((instance as double) - (instance as double).floorToDouble());
    }
  }

  /// Implements repeat, the looping primitive. (CODE 24)
  void codeFor() {
    // temps = token step stop var start exp
    final codeVec = temps[5] as StVector;
    final name = temps[3] as String? ?? '';
    var currentVal = temps[4] as num;
    final increment = temps[1] as num;
    final finalVal = temps[2] as num;
    value = null;
    final msg = message!;
    final ctxt = St72(
      instance: msg.instance,
      clss: msg.clss,
      ret: this,
      message: msg.message,
      global: msg.global,
      temps: msg.temps,
      code: codeVec,
      subEval: subEval,
    );
    mode = Mode.repeat;
    while (mode == Mode.repeat && (increment < 0 ? currentVal >= finalVal : currentVal <= finalVal)) {
      ctxt.valueAtPut(name, currentVal);
      ctxt.reset();
      ctxt.evaluate();
      currentVal += increment;
    }
    returnValue(value);
  }

  /// Implements the GET primitive. (CODE 28)
  void codeGet() {
    final clss = temps[0];
    final name = temps[1] as String;
    assert(isClass(clss));
    returnValue(getClassTable(clss)[name]);
  }

  /// Implements isnew. (CODE 5)
  void codeIsnew() {
    returnValue(message!.doIsnew());
  }

  /// (CODE 20)
  void codeKbd() {
    if (inputStream.atEnd) {
      throw 'implement real keyboard input';
    }
    returnValue(inputStream.next());
  }

  void codeMouse() => throw UnimplementedError();

  /// Implements primitive operations of integers. (CODE 4)
  void codeNumber() {
    final msg = message!;
    var token = msg.peekToken();
    if (token == null) return returnValue(instance);
    // Arithmetic ops, +, -, etc.
    if (token == '+') return advanceAndApply((a, b) => a + b);
    if (token == '-') return advanceAndApply((a, b) => a - b);
    if (token == '*') return advanceAndApply((a, b) => a * b);
    if (token == '/') return advanceAndApply((a, b) => a ~/ b);
    if (token == 'mod') return advanceAndApply((a, b) => a % b);
    if (token == '<') return advanceAndCompare((a, b) => a < b);
    if (token == '=') return advanceAndCompare((a, b) => a == b);
    if (token == '>') return advanceAndCompare((a, b) => a > b);
    if (token == '<=') return advanceAndCompare((a, b) => a <= b);
    if (token == '#') return advanceAndCompare((a, b) => a != b);
    if (token == '>=') return advanceAndCompare((a, b) => a >= b);
    if (token == '&') {
      // Logical ops, &+, &-, etc.
      msg.nextToken();
      token = msg.nextToken();
      if (token == '+') return advanceAndApply2((a, b) => a | b);
      if (token == '-') return advanceAndApply2((a, b) => a ^ b);
      if (token == '*') return advanceAndApply2((a, b) => a & b);
      if (token == '/') return advanceAndApply2((a, b) => a << b);
    }
  }

  /// Implements the PUT primitive. (CODE 12)
  void codePut() {
    final clss = temps[0];
    final name = temps[1] as String;
    final val = temps[2];
    assert(isClass(clss));
    getClassTable(clss)[name] = val;
    returnValue(null);
  }

  /// Implements read, the bootstrap read routine. (CODE 2)
  void codeRead() {
    if (temps.isNotEmpty && temps.first != null) {
      return returnValue(scan(temps.first as String));
    }
    final rd = readFrom(inputStream);
    if (rd == null) {
      // Return to the top level at end of bootstrap
      for (St72? caller = this; caller != null; caller = caller.ret) {
        caller.returnValue(null);
      }
      return;
    }
    returnValue(rd);
  }

  /// Implements repeat, the looping primitive. (CODE 1)
  void codeRepeat() {
    final msg = message!;
    final code = temps[0] as StVector;
    final ctxt = St72(
        instance: msg.instance,
        clss: msg.clss,
        ret: this,
        message: msg.message,
        global: msg.global,
        temps: msg.temps,
        code: code,
        subEval: true);
    mode = Mode.repeat;
    while (mode == Mode.repeat) {
      ctxt.reset();
      ctxt.evaluate();
    }
    returnValue(value);
  }

  /// Implements primitive operations of strings and vectors. (CODE 3)
  void codeStrVec() {
    final msg = message as St72;
    if (instance == null) {
      // isnew
      final length = fetchFrom(msg) as int;
      if (clss == Str) {
        return returnValue(Str('?' * length));
      }
      return returnValue(List<OOP>.filled(length, 3));
    }
    if (clss == List) {
      final v = instance as StVector;
      // Only vectors respond to eval
      if (msg.implicitEval(v) || matchTokenFrom('eval', msg)) {
        return returnValue(St72(
          instance: msg.instance,
          clss: msg.clss,
          ret: this,
          message: msg.message,
          global: msg,
          temps: msg.temps,
          code: v,
          subEval: true,
        ).evaluate());
      }
    }
    if (matchTokenFrom('length', msg)) {
      if (clss == Str) return returnValue((instance as Str).value.length);
      return returnValue((instance as StVector).length);
    }
    if (matchTokenFrom('[', msg)) {
      final subscript = (fetchFrom(msg) as int) - 1;
      temps[0] = subscript + 1;
      if (matchTokenFrom(']', msg)) {
        if (matchTokenFrom('_', msg)) {
          value = fetchFrom(msg);
          if (clss == Str) {
            (instance as Str)[subscript] = value as int;
          } else {
            (instance as StVector)[subscript] = value;
          }
          return returnValue(value);
        } else {
          if (clss == Str) {
            return returnValue((instance as Str)[subscript]);
          } else {
            return returnValue((instance as StVector)[subscript]);
          }
        }
      } else {
        if (matchTokenFrom('to', msg)) {
          return applyValue(true);
        } else {
          throw 'missing close bracket';
        }
      }
    }
    applyValue(false);
  }

  /// Implements primitive operations of streams. (CODE 22)
  void codeStream() {
    if (instance == null) return;
    final inst = instance as StObject;
    final msg = message!;
    final index = inst.ivars[0] as int;
    final buffer = inst.ivars[1] as StVector;
    final length = inst.ivars[2] as int;
    if (matchTokenFrom('_', msg)) {
      final val = fetchFrom(msg);
      if (index >= length) {
        throw UnimplementedError();
      }
      buffer[index] = val;
      inst.ivars[0] = index + 1;
      return returnValue(val);
    }
    if (matchTokenFrom('next', msg)) {
      if (index >= length) return returnValue(0);
      inst.ivars[0] = index + 1;
      return returnValue(buffer[index]);
    }
    if (matchTokenFrom('contents', msg)) {
      return returnValue(buffer.sublist(0, index));
    }
  }

  /// Implements the substr package. (CODE 40)
  void codeSubstr() {
    final op = temps[0] as int;
    final item = temps[1]; // int or OOP
    final s = temps[2]; // string or vector
    assert(s is Str || s is StVector);
    final lb = temps[3] as int;
    final ub = temps[4] as int;
    if (op == 0) {
      if (s is Str) {
        for (var i = lb; i <= ub; i++) {
          s[i - 1] = item as int;
        }
      } else if (s is StVector) {
        for (var i = lb; i <= ub; i++) {
          s[i - 1] = item;
        }
      }
      return returnValue(s);
    } else if (op == 1) {
      if (s is Str) {
        for (var i = lb; i <= min(ub, s.length); i++) {
          if (s[i - 1] == item) return returnValue(i);
        }
      } else if (s is StVector) {
        for (var i = lb; i <= min(ub, s.length); i++) {
          if (s[i - 1] == item) return returnValue(i);
        }
      }
      return returnValue(0);
    } else if (op == 2) {
      if (s is Str) {
        for (var i = min(ub, s.length); i >= lb; i--) {
          if (s[i - 1] == item) return returnValue(i);
        }
      } else if (s is StVector) {
        for (var i = min(ub, s.length); i >= lb; i--) {
          if (s[i - 1] == item) return returnValue(i);
        }
      }
      return returnValue(0);
    } else if (op == 3) {
      if (s is Str) {
        for (var i = lb; i <= min(ub, s.length); i++) {
          if (s[i - 1] != item) return returnValue(i);
        }
      } else if (s is StVector) {
        for (var i = lb; i <= min(ub, s.length); i++) {
          if (s[i - 1] != item) return returnValue(i);
        }
      }
      return returnValue(0);
    } else if (op == 4) {
      if (s is Str) {
        for (var i = min(ub, s.length); i >= lb; i--) {
          if (s[i - 1] != item) return returnValue(i);
        }
      } else if (s is StVector) {
        for (var i = min(ub, s.length); i >= lb; i--) {
          if (s[i - 1] != item) return returnValue(i);
        }
      }
      return returnValue(0);
    }
    final lb2 = temps[6] as int;
    if (op == 5) {
      if (s is Str) {
        final s2 = temps[5] as Str;
        final repSize = min(ub - lb, s2.length - lb2) + 1;
        final ss = s.value.substring(0, lb + repSize - 2) + //
            s2.value.substring(lb2 - 1) +
            s.value.substring(lb + repSize - 1);
        return returnValue(Str(ss));
      } else if (s is StVector) {
        final s2 = temps[5] as StVector;
        final repSize = min(ub - lb, s2.length - lb2) + 1;
        s.replaceRange(lb + repSize - 1, lb + repSize - 1, s2.sublist(lb2 - 1));
        return returnValue(s);
      }
    } else if (op == 6) {
      if (s is Str) {
        if (ub > s.length) {
          return returnValue(Str(s.value.substring(lb - 1) + '?' * (ub - s.length)));
        }
        return returnValue(Str(s.value.substring(lb - 1, ub - 1)));
      } else if (s is StVector) {
        if (ub > s.length) {
          final ss = s.sublist(lb - 1) + List<OOP>.filled(ub - s.length, null);
          return returnValue(ss);
        }
        return returnValue(s.sublist(lb - 1, ub - 1));
      }
    }
  }

  void codeTextFrame() => throw UnimplementedError();

  /// Implements to, the class-defining primitive. (CODE 19)
  void codeTo() {
    final msg = message!;
    final title = msg.nextToken() as String;
    final temps = <String>[];
    final ivars = <String>[];
    final cvars = <String>[];
    var token = msg.nextToken();
    while (isAtom(token) && token != ':') {
      temps.add(token as String);
      token = msg.nextToken();
    }
    if (token is StVector) {
      return _define(title, temps, ivars, cvars, token);
    }
    if (token == ':') {
      token = msg.nextToken();
    } else {
      throw 'missing :';
    }
    while (isAtom(token) && token != ':') {
      ivars.add(token as String);
      token = msg.nextToken();
    }
    if (token is StVector) {
      return _define(title, temps, ivars, cvars, token);
    }
    if (token == ':') {
      token = msg.nextToken();
    } else {
      throw 'missing :';
    }
    while (isAtom(token) && token != ':') {
      cvars.add(token as String);
      token = msg.nextToken();
    }
    if (token is StVector) {
      return _define(title, temps, ivars, cvars, token);
    }
    throw 'missing code vector';
  }

  /// Implements primitive operations of turtles. (CODE 21)
  void codeTurtle() {
    final msg = message!;
    if (matchTokenFrom('go', msg)) {
      realPenFromInstanceDo(instance, (pen) => pen.go(fetch() as int));
    } else if (matchTokenFrom('turn', msg)) {
      realPenFromInstanceDo(instance, (pen) => pen.turn(fetch() as int));
    } else if (matchTokenFrom('goto', msg)) {
      realPenFromInstanceDo(instance, (pen) => pen.goto(fetch() as int, fetch() as int));
    }
  }

  // ---- code support ---

  void advanceAndApply(num Function(num, num) selector) {
    message!.nextToken();
    returnValue(selector(instance as num, fetchFrom(message!) as num));
  }

  void advanceAndApply2(num Function(int, int) selector) {
    message!.nextToken();
    returnValue(selector(instance as int, fetchFrom(message!) as int));
  }

  void advanceAndCompare(bool Function(num, num) selector) {
    message!.nextToken();
    final arg = fetchFrom(message!);
    if (arg == false) return returnValue(false);
    returnValue(selector(instance as num, arg as num) ? instance : false);
  }

  // compareTo: arg as: comparisonBlock
  // dispFrame: inst
  // dispWindow: inst

  /// Implements isnew.
  OOP doIsnew() {
    if (instance != null) return false;
    if (clss == bool) {
      instance = false;
    } else {
      instance = (clss as StClass).create();
    }
    return true;
  }

  OOP fetch() {
    if (message!.peekToken() == '.') return null;
    return message!.evalOnce();
  }

  // fetchRect
  // findTokenIndexOf: char in: str
  // nextAndFetch
  // realParagraphFrom: inst do: aBlock

  void realPenFromInstanceDo(OOP instance, void Function(StPen) block) {
    final inst = instance as StObject;
    final pen = St72.pen ??= StPen();
    final width = inst.ivars[2] as int;
    pen.width = width;
    final color = inst.ivars[1];
    if (color is int) {
      pen.color = StPenColor.values[color];
    } else if (color is String) {
      pen.color == StPenColor.values.singleWhere((c) => '$c'.endsWith(color));
    } else {
      throw 'invalid color';
    }
    pen.x = (inst.ivars[5] as int) - width ~/ 2;
    pen.y = (inst.ivars[6] as int) - width ~/ 2;
    pen.direction = inst.ivars[3] as int;
    pen.isDown = inst.ivars[0] == 1;
    pen.isReverse = inst.ivars[4] == 1;
    block(pen);
    inst.ivars[3] = pen.direction;
    inst.ivars[5] = pen.x + width ~/ 2;
    inst.ivars[6] = pen.y + width ~/ 2;
  }

  static StPen? pen;

  // scrollParagraph: para

  // this should and could be a table with 70 entries
  void primitive(int code) {
    switch (code) {
      case 1:
        return codeRepeat();
      case 2:
        return codeRead();
      case 3:
        return codeStrVec();
      case 4:
        return codeNumber();
      case 5:
        return codeIsnew();
      case 6:
        return codeAgain();
      case 11:
        return codeFalse();
      case 12:
        return codePut();
      case 15:
        return codeEq();
      case 19:
        return codeTo();
      case 20:
        return codeKbd();
      case 21:
        return codeTurtle();
      case 22:
        return codeStream();
      case 23:
        return codeDisp();
      case 24:
        return codeFor();
      case 25:
        return codeDone();
      case 28:
        return codeGet();
      case 29:
        return codeAtom();
      case 40:
        return codeSubstr();
      case 42:
        return codeFloat();
      default:
        throw 'missing primitive $code';
    }
  }

  /// Create a new class, or identify an existing one or Squeak equivalent.
  void _define(
    String title,
    List<String> temps,
    List<String> ivars,
    List<String> cvars,
    StVector code,
  ) {
    const mapping = <String, Type>{
      'number': int,
      'vector': List,
      'atom': String,
      'string': Str,
      'arec': St72,
      'float': double,
      'falseclass': bool,
    };
    final clss = mapping[title] ?? global!.bootValueAt(title) ?? StClass(title, ivars);
    final dict = title == 'USER' ? TopLev : <String, OOP>{};
    setClassTable(clss, dict);

    dict['TABLE'] = dict;
    for (var i = 0; i < temps.length; i++) {
      dict[temps[i]] = St72Accessor(St72AccessorType.temp, i);
    }
    for (var i = 0; i < ivars.length; i++) {
      dict[ivars[i]] = St72Accessor(St72AccessorType.ivar, i);
    }
    for (var i = 0; i < cvars.length; i++) {
      dict[cvars[i]] ??= null;
    }
    dict['TITLE'] = title;
    dict['DO'] = code;
    dict['ARSIZE'] = temps.length;
    global!.bootValueAtPut(title, clss);

    if (this.temps.isNotEmpty) this.temps[0] = title;
    value = title;
  }

  // ---- initialize ----

  static late InputStream inputStream;
  static late StringSink transcript;

  // ---- bootstrap reader ----

  static void bootFrom(String contents, StringSink sink) {
    _classTableForArray.clear();
    _classTableForAtom.clear();
    _classTableForFalse.clear();
    _classTableForFloat.clear();
    _classTableForNumber.clear();
    _classTableForString.clear();

    TopLev.clear();

    inputStream = InputStream(contents);
    transcript = sink;

    while (!inputStream.atEnd) {
      final user = TopLev['USER'];
      if (user != null) {
        transcript.writeln(runAsUserCode(getClassTable(user)['DO'] as StVector));
      } else {
        transcript.writeln(eval1(readFrom(inputStream)!));
      }
    }

    transcript.writeln('''
To start Smalltalk-72 for the first time, execute (select and cmd-d) this line...
	t USER

To restart Smalltalk after closing errors, execute this line...
	disp show. disp frame. USER

After the Alto prompt, type any expression followed by doit
	for doit,				type the cursor-up key
	for open-colon,		type the semicolon key
	for apostrophe-s,	type the open-string-quote key

You can re-execute something you have already typed by
 	redo
or edit it for re-execution by
	fix
You can access earlier do-its with, eg, redo 2 or fix 3.

You can edit a function or class by typing, eg,
	edit factorial''');
  }

  /// Set up context for evaluating at top level.
  static OOP runAsUserCode(StVector vec) {
    final user = TopLev['USER'];
    return St72(
      instance: null,
      clss: user,
      ret: null,
      message: null,
      global: null,
      temps: List<OOP>.filled(getClassTable(user)['ARSIZE'] as int, null),
      code: vec,
      subEval: false,
    ).evaluate();
  }

  static void runAsUserText(String text) {
    runAsUserCode([scan(text), ...scan('print.cr')]);
  }

  /// Bootstrap eval routine until ST72 is alive.
  static OOP eval1(StVector vec) {
    if (vec.isEmpty) return vec;
    if (vec.length == 1 && vec.first is Str) return vec;
    if (vec.first == 'to') {
      final topCtxt = St72(
        instance: null,
        clss: null,
        ret: null,
        message: null,
        global: null,
        temps: <OOP>[],
        code: vec.sublist(1),
        subEval: false,
      );
      final toCtxt = St72(
        instance: null,
        clss: null,
        ret: topCtxt,
        message: topCtxt,
        global: topCtxt,
        temps: <OOP>[],
        code: ['CODE', 19],
        subEval: false,
      );
      toCtxt.codeTo();
      return toCtxt.value;
    }
    throw 'bootstrap reader can only process class defs';
  }

  static StVector? readFrom(InputStream inputStream) {
    final buffer = StringBuffer();
    var parCount = 0;
    var strCount = 0;
    while (!inputStream.atEnd) {
      final line = inputStream.readLine();
      for (var i = 0; i < line.length; i++) {
        if (line[i] == '\'') strCount++;
        if (strCount.isOdd) continue;
        if (line[i] == '(') parCount++;
        if (line[i] == ')') parCount--;
      }
      buffer.writeln(line);
      if (parCount == 0 && strCount.isEven) {
        final vec = dropComments(scan(buffer.toString()));
        if (vec.isEmpty) return readFrom(inputStream);
        transcript.writeln(vec);
        return vec;
      }
    }
    return null;
  }

  static StVector dropComments(StVector vec) {
    return vec.where((o) => o is! Str).map((o) => o is StVector ? dropComments(o) : o).toList();
  }
}

/// Access type, see [St72Accessor.type].
enum St72AccessorType { temp, ivar }

/// A way to access either temporaries/parameters or instance variables.
class St72Accessor {
  const St72Accessor(this.type, this.index);

  final St72AccessorType type;
  final int index;

  OOP getValueForTempsOrInstance(StVector temps, OOP instance) {
    if (type == St72AccessorType.temp) return temps[index];
    if (type == St72AccessorType.ivar) return (instance as StObject).ivars[index];
    throw Error();
  }

  T putValueIntoTempsOrInstance<T>(T value, StVector temps, OOP instance) {
    if (type == St72AccessorType.temp) return temps[index] = value;
    if (type == St72AccessorType.ivar) return (instance as StObject).ivars[index] = value;
    throw Error();
  }
}

/// Represents an instance of some class that has private memory.
class StObject {
  StObject(this.clss, this.ivars);

  final StClass clss;
  final StVector ivars;

  @override
  String toString() => 'a ${clss.name} instance';
}

/// Represents a class object.
class StClass {
  StClass(this.name, this.ivars);

  final String name;
  final List<String> ivars;
  StDictionary classTable = {};

  StObject create() {
    return StObject(this, List<OOP>.filled(ivars.length, null));
  }

  @override
  String toString() => 'St72Class($name, $ivars, ${classTable.keys.toList()})';
}

/// Returns whether [object] is an atom or not.
bool isAtom(OOP object) => object is String;

/// Returns whether [object] is a class object (and not an instance).
bool isClass(OOP object) => object is Type || object is StClass;

/// Workaround because I use Dart's [String] for atoms (a.k.a. symbols).
class Str {
  Str(this.value);

  /*final*/ String value;

  int get length => value.length;

  int operator [](int index) => value.codeUnitAt(index);

  operator []=(int index, int ch) {
    value = value.substring(0, index) + String.fromCharCode(ch) + value.substring(index + 1);
  }

  @override
  bool operator ==(dynamic other) => other is Str && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

// method dictionaries for built-in classes, see [getClassTable]
var _classTableForArray = <String, OOP>{};
var _classTableForAtom = <String, OOP>{};
var _classTableForFalse = <String, OOP>{};
var _classTableForFloat = <String, OOP>{};
var _classTableForNumber = <String, OOP>{};
var _classTableForString = <String, OOP>{};

/// Returns the class of [object], either a built-in [Type] or a [StClass] instance.
OOP classOf(OOP object) {
  if (object == null) return null;
  if (object is StObject) return object.clss;
  if (object is StVector) return List; // hack, cannot use List<OOP> here
  return object.runtimeType;
}

/// Returns the method dictionary associated with [clss].
StDictionary getClassTable(OOP clss) {
  assert(isClass(clss));
  if (clss == List) return _classTableForArray;
  if (clss == String) return _classTableForAtom;
  if (clss == bool) return _classTableForFalse;
  if (clss == double) return _classTableForFloat;
  if (clss == int) return _classTableForNumber;
  if (clss == Str) return _classTableForString;
  if (clss is StClass) return clss.classTable;
  throw 'missing class table for $clss';
}

/// Overwrites the method dictionary of [clss] with [classTable].
void setClassTable(Object clss, StDictionary classTable) {
  assert(isClass(clss));
  if (clss == List) {
    _classTableForArray = classTable;
  } else if (clss == String) {
    _classTableForAtom = classTable;
  } else if (clss == bool) {
    _classTableForFalse = classTable;
  } else if (clss == double) {
    _classTableForFloat = classTable;
  } else if (clss == int) {
    _classTableForNumber = classTable;
  } else if (clss == Str) {
    _classTableForString = classTable;
  } else if (clss is StClass) {
    clss.classTable = classTable;
  } else {
    throw 'missing class table for $clss';
  }
}

enum StPenColor { black, white }

class StPen {
  int width = 256;
  StPenColor color = StPenColor.black;
  int x = 0;
  int y = 0;
  int direction = 0;
  bool isDown = false;
  bool isReverse = false;

  void go(int steps) {
    final a = direction * pi / 180;
    goto(
      x + (steps * cos(a)).round(),
      y + (steps * sin(a)).round(),
    );
  }

  void turn(int angle) {
    direction = (direction + angle) % 360;
    print('@ turn to $direction°');
  }

  void goto(int xx, int yy) {
    print('@ moves from $x,$y to $xx,$yy');
    x = xx;
    y = yy;
  }
}

// Dart compatibility stuff

/// Splits [s] into atoms, numbers, strings, and vectors or such elements.
StVector scan(String s) {
  final stack = <StVector>[<OOP>[]];
  final re = RegExp(
      "'(.*?)'|(-?\\d+(?:\\.\\d+)?)|([a-zA-Z][a-zA-Z0-9]*|[.\"_%:!#?~\\[\\]=><\\-+*/&{},@\$;\u2982\u275C])|[()]|([^\t\r\n ])",
      dotAll: true);
  for (final m in re.allMatches(s)) {
    if (m[1] != null) {
      stack.last.add(Str(m[1]!)); // String
    } else if (m[2] != null) {
      stack.last.add(num.parse(m[2]!)); // Number or Float
    } else if (m[3] != null) {
      stack.last.add(m[3]!); // Atom
    } else if (m[0] == '(') {
      stack.add(<OOP>[]);
    } else if (m[0] == ')') {
      final vec = stack.removeLast();
      stack.last.add(vec);
    } else {
      throw 'unknown character ${m[0]!.codeUnitAt(0)}';
    }
  }
  return stack.single;
}

/// Provides access to a stream of characters, either line by line or
/// character by character. Notice that lines are separated by `\r`.
class InputStream {
  InputStream(this.source) : _index = 0;

  final String source;

  int _index;

  /// Returns whether the stream has reached its end.
  bool get atEnd => _index == source.length;

  /// Returns the next character from the stream or `0` if it reached its end.
  int next() => atEnd ? 0 : source.codeUnitAt(_index++);

  /// Returns the next line from the stream or `''` if it reached its end.
  String readLine() {
    final i = source.indexOf('\r', _index);
    if (i == -1) {
      final line = source.substring(_index);
      _index = source.length;
      return line;
    }
    final line = source.substring(_index, i);
    _index = i + 1;
    return line;
  }
}
