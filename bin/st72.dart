import 'dart:io';

import 'package:st72/st72.dart';

void main() {
  St72.bootFrom(File('ALLDEFS').readAsStringSync(), stderr);
  St72.transcript = stdout;
  St72.runAsUserText('3+4');
  St72.runAsUserText('355.0/113');
  St72.runAsUserText('show for');
  St72.runAsUserText('"newAtom_6.newAtom');
}
