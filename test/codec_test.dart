import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hzmi_powerrune_remote/ble/codec.dart';

void main() {
  group('RuneCodec', () {
    test('encodes run options in protocol order', () {
      const cfg = RunCfg(
        color: TeamColor.blue,
        mode: RuneMode.small,
        loop: true,
        dir: SpinDir.counterClockwise,
      );

      expect(RuneCodec.run(cfg), [1, 1, 1, 1]);
    });

    test('encodes and decodes little-endian PID values', () {
      const input = PidData(
        kp: 1.25,
        ki: -2.5,
        kd: 3.75,
        iMax: 4,
        dMax: 5.5,
        outMax: 6.25,
      );

      final bytes = RuneCodec.pid(input);
      final first = ByteData.sublistView(bytes).getFloat32(0, Endian.little);
      final output = RuneCodec.readPid(bytes);

      expect(bytes, hasLength(24));
      expect(first, 1.25);
      expect(output.values, input.values);
    });

    test('encodes debug commands with little-endian float payload', () {
      final bytes = RuneCodec.debugCommand(3, 0, value: 1.5);
      expect(bytes, hasLength(8));
      expect(bytes[0], 3);
      expect(bytes[1], 0);
      expect(bytes[2], 0);
      expect(bytes[3], 0);
      expect(ByteData.sublistView(bytes).getFloat32(4, Endian.little), 1.5);
    });

    test('parses score notifications and removes nul bytes', () {
      final msg = RuneCodec.notice([
        ...'[Score: 12]PowerRune Activated Successfully'.codeUnits,
        0,
      ]);

      expect(msg.type, RuneMsgType.score);
      expect(msg.score, 12);
    });

    test('parses run lifecycle notifications', () {
      expect(
        RuneCodec.notice('PowerRune Start with Color Red'.codeUnits).type,
        RuneMsgType.start,
      );
      expect(
        RuneCodec.notice('PowerRune Activation Failed'.codeUnits).type,
        RuneMsgType.failed,
      );
      expect(
        RuneCodec.notice('PowerRune Run Complete'.codeUnits).type,
        RuneMsgType.complete,
      );
    });
  });
}
