import 'package:flutter_blue_plus/flutter_blue_plus.dart';

abstract final class BleIds {
  static final configService = Guid('1827');
  static final runService = Guid('1828');

  static final armourLight = Guid('2a0d');
  static final edgeLight = Guid('2a01');
  static final logoLight = Guid('2a9b');
  static final matrixLight = Guid('2a9c');
  static final pid = Guid('2a66');
  static final resetId = Guid('2b1f');
  static final boardStatus = Guid('2af0');
  static final debug = Guid('2af1');

  static final run = Guid('2a65');
  static final scores = Guid('2a69');
  static final unlock = Guid('2a3b');
  static final stop = Guid('2ac8');
}
