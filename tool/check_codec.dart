import 'package:hzmi_powerrune_remote/ble/codec.dart';

void main() {
  const cfg = RunCfg(
    color: TeamColor.blue,
    mode: RuneMode.small,
    loop: true,
    dir: SpinDir.counterClockwise,
  );
  if (RuneCodec.run(cfg).join(',') != '1,1,1,1') {
    throw StateError('RUN 编码失败');
  }

  const pid = PidData(
    kp: 1.25,
    ki: -2.5,
    kd: 3.75,
    iMax: 4,
    dMax: 5.5,
    outMax: 6.25,
  );
  final decoded = RuneCodec.readPid(RuneCodec.pid(pid));
  if (decoded.values.join(',') != pid.values.join(',')) {
    throw StateError('PID 编解码失败');
  }

  final msg = RuneCodec.notice(
    '[Score: 12]PowerRune Activated Successfully\x00'.codeUnits,
  );
  if (msg.type != RuneMsgType.score || msg.score != 12) {
    throw StateError('成绩通知解析失败');
  }
}
