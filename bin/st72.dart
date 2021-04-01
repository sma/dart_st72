import 'dart:io';

import 'package:st72/st72.dart';

void main() {
  St72.bootFrom(File('ALLDEFS').readAsStringSync(), stderr);
  St72.transcript = stdout;
  St72.runAsUserText('3+4');
  St72.runAsUserText('355.0/113');
  St72.runAsUserText('show for');
  St72.runAsUserText('"newAtom_6.newAtom');

  St72.runAsUserText('@ go 50');
  St72.runAsUserText('@ turn 90 go 50');
  St72.runAsUserText('do 4 (@ go 50 turn 90)');
  St72.runAsUserText('@ home up');
  St72.runAsUserText('to square size (:size. do 4 (@ go size turn 90))');
  St72.runAsUserText('square 20');
  St72.runAsUserText('for i to 200 by 10 (square i)');
  St72.runAsUserText('to spiral angle n d ((:angle. :n. :d. for i to n by d (@ go i turn angle)))');
  St72.runAsUserText('spiral 89 400 2');
  St72.runAsUserText('@ is ~'); // NB: ? is ⇒, but ~ is ?
  St72.runAsUserText('@ is number');
}
