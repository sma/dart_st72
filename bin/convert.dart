import 'dart:io';

void main(List<String> args) {
  final f = File(args.isEmpty ? 'ALLDEFS' : args.first);
  var s = f.readAsStringSync();
  s = s.replaceAll('\r\n', '\r');
  s = s.replaceAll('\x03', '⦂');
  s = s.replaceAll('\x0F', '`');
  s = s.replaceAll('\x11', '');
  s = s.replaceAll('\x13', '❜');
  f.writeAsStringSync(s);
  final invisible = <int>{};
  for (var i = 0; i < s.length; i++) {
    final b = s.codeUnitAt(i);
    if (b < 32) invisible.add(b);
  }
  print(invisible.toList()..sort());
}
