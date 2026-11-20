import 'dart:convert';
import 'dart:typed_data';

enum TeamColor { red, blue }

enum RuneMode { big, small }

enum SpinDir { clockwise, counterClockwise }

class RunCfg {
  const RunCfg({
    this.color = TeamColor.red,
    this.mode = RuneMode.big,
    this.loop = false,
    this.dir = SpinDir.clockwise,
  });

  final TeamColor color;
  final RuneMode mode;
  final bool loop;
  final SpinDir dir;

  RunCfg copyWith({
    TeamColor? color,
    RuneMode? mode,
    bool? loop,
    SpinDir? dir,
  }) {
    return RunCfg(
      color: color ?? this.color,
      mode: mode ?? this.mode,
      loop: loop ?? this.loop,
      dir: dir ?? this.dir,
    );
  }
}

class PidData {
  const PidData({
    required this.kp,
    required this.ki,
    required this.kd,
    required this.iMax,
    required this.dMax,
    required this.outMax,
  });

  const PidData.zero() : kp = 0, ki = 0, kd = 0, iMax = 0, dMax = 0, outMax = 0;

  final double kp;
  final double ki;
  final double kd;
  final double iMax;
  final double dMax;
  final double outMax;

  List<double> get values => [kp, ki, kd, iMax, dMax, outMax];
}

enum RuneMsgType { start, score, failed, complete, text }

class RuneMsg {
  const RuneMsg(this.type, this.text, {this.score});

  final RuneMsgType type;
  final String text;
  final int? score;
}

abstract final class RuneCodec {
  static final _score = RegExp(
    r'\[Score:\s*(\d+)\]PowerRune Activated Successfully',
  );

  static Uint8List run(RunCfg cfg) {
    return Uint8List.fromList([
      cfg.color == TeamColor.blue ? 1 : 0,
      cfg.mode == RuneMode.small ? 1 : 0,
      cfg.loop ? 1 : 0,
      cfg.dir == SpinDir.counterClockwise ? 1 : 0,
    ]);
  }

  static Uint8List pid(PidData data) {
    final bytes = ByteData(24);
    for (var i = 0; i < data.values.length; i++) {
      bytes.setFloat32(i * 4, data.values[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  static Uint8List debugCommand(int command, int argument, {double value = 0}) {
    if (!value.isFinite) throw const FormatException('调试参数必须是有限数字');
    final bytes = ByteData(8)
      ..setUint8(0, command & 0xff)
      ..setUint8(1, argument & 0xff)
      ..setFloat32(4, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  static PidData readPid(List<int> value) {
    if (value.length != 24) {
      throw const FormatException('PID 数据长度应为 24 字节');
    }
    final data = ByteData.sublistView(Uint8List.fromList(value));
    final values = List<double>.generate(
      6,
      (i) => data.getFloat32(i * 4, Endian.little),
    );
    return PidData(
      kp: values[0],
      ki: values[1],
      kd: values[2],
      iMax: values[3],
      dMax: values[4],
      outMax: values[5],
    );
  }

  static RuneMsg notice(List<int> value) {
    final clean = value.where((byte) => byte != 0).toList();
    final text = utf8.decode(clean, allowMalformed: true).trim();
    final match = _score.firstMatch(text);
    if (match != null) {
      return RuneMsg(
        RuneMsgType.score,
        text,
        score: int.tryParse(match.group(1)!),
      );
    }
    if (text.contains('PowerRune Run Complete')) {
      return RuneMsg(RuneMsgType.complete, text);
    }
    if (text.contains('PowerRune Activation Failed')) {
      return RuneMsg(RuneMsgType.failed, text);
    }
    if (text.contains('PowerRune Start with')) {
      return RuneMsg(RuneMsgType.start, text);
    }
    return RuneMsg(RuneMsgType.text, text);
  }
}
