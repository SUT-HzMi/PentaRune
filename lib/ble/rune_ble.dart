import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'codec.dart';
import 'ids.dart';

enum LinkState { idle, scanning, connecting, loading, ready, retrying, error }

enum RunState { idle, starting, running, stopping, unknown }

class RuneLog {
  const RuneLog(this.time, this.text, this.type);

  final DateTime time;
  final String text;
  final RuneMsgType type;
}

class RuneBle extends ChangeNotifier {
  RuneBle() {
    _scanSub = FlutterBluePlus.onScanResults.listen(
      _onScan,
      onError: (Object error) => _fail('扫描失败：$error'),
    );
    _scanStateSub = FlutterBluePlus.isScanning.listen((value) {
      if (!value && link == LinkState.scanning) {
        link = LinkState.idle;
        notifyListeners();
      }
    });
  }

  LinkState link = LinkState.idle;
  RunState runState = RunState.idle;
  bool demo = false;
  RunCfg runCfg = const RunCfg();
  String? error;
  int? rssi;
  int mtu = 23;
  int armourLight = 0;
  int edgeLight = 0;
  int logoLight = 0;
  int matrixLight = 0;
  PidData pid = const PidData.zero();
  int? latestScore;
  List<int> scores = const [];
  List<ScanResult> found = const [];
  final List<RuneLog> logs = [];

  BluetoothDevice? _device;
  final Map<Guid, BluetoothCharacteristic> _chars = {};
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _scanStateSub;
  StreamSubscription<BluetoothConnectionState>? _linkSub;
  StreamSubscription<List<int>>? _noticeSub;
  StreamSubscription<int>? _mtuSub;
  Timer? _retryTimer;
  Timer? _cmdTimer;
  final List<Timer> _demoTimers = [];
  bool _manualOff = false;
  bool _linked = false;
  int _retryCount = 0;

  bool get ready => link == LinkState.ready;
  bool get connected => demo || (_device?.isConnected ?? false);
  String get name => demo
      ? 'SimuRune'
      : _device?.platformName.isNotEmpty == true
      ? _device!.platformName
      : 'PowerRune';
  String? get remoteId => demo ? 'DEMO-SIMURUNE' : _device?.remoteId.str;

  Future<void> scan() async {
    if (connected) return;
    error = null;
    link = LinkState.scanning;
    found = const [];
    notifyListeners();
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 12),
        continuousUpdates: true,
        removeIfGone: const Duration(seconds: 4),
        webOptionalServices: [BleIds.configService, BleIds.runService],
      );
    } catch (e) {
      _fail('无法开始扫描：$e');
    }
  }

  Future<void> connect(ScanResult result) async {
    _manualOff = false;
    _retryCount = 0;
    _device = result.device;
    rssi = result.rssi;
    await _open();
  }

  Future<void> _open() async {
    final device = _device;
    if (device == null) return;
    _retryTimer?.cancel();
    error = null;
    link = _retryCount == 0 ? LinkState.connecting : LinkState.retrying;
    notifyListeners();

    try {
      await FlutterBluePlus.stopScan();
      await _linkSub?.cancel();
      _linkSub = device.connectionState.listen(_onLink);
      if (!device.isConnected) {
        await device.connect(
          license: License.nonprofit,
          mtu: 64,
          timeout: const Duration(seconds: 15),
        );
      }
      _linked = true;
      link = LinkState.loading;
      notifyListeners();
      await _load(device);
      _retryCount = 0;
      link = LinkState.ready;
      runState = runState == RunState.unknown
          ? RunState.unknown
          : RunState.idle;
      rssi = await device.readRssi();
      notifyListeners();
    } catch (e) {
      _linked = false;
      _fail('连接失败：$e');
    }
  }

  Future<void> disconnect() async {
    if (demo) {
      await setDemo(false);
      return;
    }
    _manualOff = true;
    _linked = false;
    _retryTimer?.cancel();
    final device = _device;
    await _clearSession();
    if (device?.isConnected == true) {
      await device!.disconnect();
    }
    _device = null;
    link = LinkState.idle;
    runState = RunState.idle;
    notifyListeners();
  }

  Future<void> start() async {
    if (demo) {
      _demoStart();
      return;
    }
    final chr = _need(BleIds.run);
    _cmdTimer?.cancel();
    runState = RunState.starting;
    notifyListeners();
    try {
      await chr.write(RuneCodec.run(runCfg), withoutResponse: true);
      _log('启动命令已发送', RuneMsgType.text);
      _waitForConfirm(RunState.starting, '未收到启动确认');
      notifyListeners();
    } catch (e) {
      runState = RunState.unknown;
      _fail('启动命令发送失败：$e', keepLink: true);
    }
  }

  Future<void> stop() async {
    if (demo) {
      _demoStop();
      return;
    }
    final chr = _need(BleIds.stop);
    _cmdTimer?.cancel();
    runState = RunState.stopping;
    notifyListeners();
    try {
      await chr.write([0], withoutResponse: true);
      _log('停止命令已发送', RuneMsgType.text);
      _waitForConfirm(RunState.stopping, '未收到停止确认');
      notifyListeners();
    } catch (e) {
      runState = RunState.unknown;
      _fail('停止命令发送失败：$e', keepLink: true);
    }
  }

  void setRun(RunCfg value) {
    runCfg = value;
    notifyListeners();
  }

  Future<void> setLight(Guid id, int value) async {
    if (demo) {
      _setLightValue(id, value);
      _log('模拟亮度已设置为 $value', RuneMsgType.text);
      notifyListeners();
      return;
    }
    final old = _light(id);
    _setLightValue(id, value);
    notifyListeners();
    try {
      await _need(id).write([value], withoutResponse: true);
    } catch (e) {
      _setLightValue(id, old);
      _fail('亮度设置失败：$e', keepLink: true);
    }
  }

  Future<void> setPid(PidData value) async {
    if (value.values.any((item) => !item.isFinite)) {
      throw const FormatException('PID 参数必须是有限数字');
    }
    if (demo) {
      pid = value;
      _log('模拟 PID 参数已应用', RuneMsgType.text);
      notifyListeners();
      return;
    }
    final device = _device;
    if (device == null) throw StateError('设备未连接');
    if (device.mtuNow < 27) {
      try {
        mtu = await device.requestMtu(64, predelay: 0);
      } catch (_) {
        // iOS negotiates MTU automatically and does not expose requestMtu.
      }
    }
    mtu = device.mtuNow;
    if (mtu < 27) {
      throw StateError('当前 MTU 为 $mtu，无法写入 24 字节 PID 数据');
    }
    await _need(BleIds.pid).write(RuneCodec.pid(value), withoutResponse: true);
    pid = value;
    _log('PID 参数已发送', RuneMsgType.text);
    notifyListeners();
  }

  Future<void> refresh() async {
    if (demo) {
      _log('模拟设备数据已刷新', RuneMsgType.text);
      notifyListeners();
      return;
    }
    if (!ready) return;
    await _readAll();
    notifyListeners();
  }

  Future<void> unlock() async {
    if (demo) {
      _log('模拟电机解锁命令已发送', RuneMsgType.text);
      notifyListeners();
      return;
    }
    await _need(BleIds.unlock).write([0], withoutResponse: true);
    _log('电机解锁命令已发送', RuneMsgType.text);
    notifyListeners();
  }

  Future<void> resetId() async {
    if (demo) {
      _log('模拟装甲板 ID 重置命令已发送', RuneMsgType.text);
      notifyListeners();
      return;
    }
    await _need(BleIds.resetId).write([0], withoutResponse: true);
    _log('装甲板 ID 重置命令已发送', RuneMsgType.text);
    notifyListeners();
  }

  Future<void> setDemo(bool value) async {
    if (demo == value) return;
    _cancelDemoTimers();
    _retryTimer?.cancel();
    _cmdTimer?.cancel();

    if (value) {
      _manualOff = true;
      _linked = false;
      await FlutterBluePlus.stopScan();
      final device = _device;
      await _clearSession();
      if (device?.isConnected == true) {
        await device!.disconnect(queue: false, androidDelay: 0);
      }
      _device = null;
      demo = true;
      link = LinkState.ready;
      runState = RunState.idle;
      error = null;
      rssi = -42;
      mtu = 64;
      armourLight = 180;
      edgeLight = 140;
      logoLight = 200;
      matrixLight = 160;
      pid = const PidData(
        kp: 1.2,
        ki: 0.08,
        kd: 0.15,
        iMax: 30,
        dMax: 20,
        outMax: 100,
      );
      scores = const [12, 10, 15, 8, 11, 13, 9, 14, 7, 12];
      latestScore = null;
      logs.clear();
      _log('模拟设备已连接', RuneMsgType.text);
      notifyListeners();
      return;
    }

    demo = false;
    link = LinkState.idle;
    runState = RunState.idle;
    error = null;
    rssi = null;
    mtu = 23;
    scores = const [];
    latestScore = null;
    logs.clear();
    notifyListeners();
    unawaited(scan());
  }

  void _demoStart() {
    _cancelDemoTimers();
    runState = RunState.starting;
    _log('模拟启动命令已发送', RuneMsgType.text);
    notifyListeners();

    _demoTimers.add(
      Timer(const Duration(milliseconds: 650), () {
        _onNotice('PowerRune Start with simulated parameters.'.codeUnits);
      }),
    );

    if (runCfg.loop) {
      _demoTimers.add(
        Timer.periodic(const Duration(seconds: 2), (_) => _demoScore()),
      );
    } else {
      _demoTimers.add(Timer(const Duration(seconds: 2), _demoScore));
      _demoTimers.add(
        Timer(const Duration(milliseconds: 3400), () {
          _onNotice('PowerRune Run Complete'.codeUnits);
        }),
      );
    }
  }

  void _demoStop() {
    _cancelDemoTimers();
    runState = RunState.stopping;
    _log('模拟停止命令已发送', RuneMsgType.text);
    notifyListeners();
    _demoTimers.add(
      Timer(const Duration(milliseconds: 500), () {
        _onNotice('PowerRune Run Complete'.codeUnits);
      }),
    );
  }

  void _demoScore() {
    final score = 8 + ((scores.isEmpty ? 0 : scores.first) + 3) % 8;
    _onNotice('[Score: $score]PowerRune Activated Successfully'.codeUnits);
  }

  void _cancelDemoTimers() {
    for (final timer in _demoTimers) {
      timer.cancel();
    }
    _demoTimers.clear();
  }

  Future<void> _load(BluetoothDevice device) async {
    await _noticeSub?.cancel();
    await _mtuSub?.cancel();
    _chars.clear();
    _mtuSub = device.mtu.listen((value) {
      mtu = value;
      notifyListeners();
    });

    final services = await device.discoverServices();
    for (final service in services) {
      if (service.uuid != BleIds.configService &&
          service.uuid != BleIds.runService) {
        continue;
      }
      for (final chr in service.characteristics) {
        _chars[chr.uuid] = chr;
      }
    }

    for (final id in [
      BleIds.run,
      BleIds.stop,
      BleIds.scores,
      BleIds.unlock,
      BleIds.armourLight,
      BleIds.edgeLight,
      BleIds.logoLight,
      BleIds.matrixLight,
      BleIds.pid,
      BleIds.resetId,
    ]) {
      _need(id);
    }

    final runChr = _need(BleIds.run);
    _noticeSub = runChr.onValueReceived.listen(_onNotice);
    await runChr.setNotifyValue(true);
    await _readAll();
  }

  Future<void> _readAll() async {
    scores = await _read(BleIds.scores);
    armourLight = _one(await _read(BleIds.armourLight));
    edgeLight = _one(await _read(BleIds.edgeLight));
    logoLight = _one(await _read(BleIds.logoLight));
    matrixLight = _one(await _read(BleIds.matrixLight));
    final pidBytes = await _read(BleIds.pid);
    if (pidBytes.length == 24) pid = RuneCodec.readPid(pidBytes);
  }

  Future<List<int>> _read(Guid id) async {
    try {
      return await _need(id).read();
    } catch (_) {
      return const [];
    }
  }

  void _onScan(List<ScanResult> results) {
    final matches = results.where((result) {
      final advName = result.advertisementData.advName.toLowerCase();
      final deviceName = result.device.platformName.toLowerCase();
      return advName == 'hertz_dafu' || deviceName == 'hertz_dafu';
    }).toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    found = matches;
    notifyListeners();
  }

  void _onLink(BluetoothConnectionState state) {
    if (state != BluetoothConnectionState.disconnected || !_linked) return;
    _linked = false;
    unawaited(_clearSession());
    runState = RunState.unknown;
    if (_manualOff) {
      link = LinkState.idle;
      notifyListeners();
      return;
    }
    if (_retryCount >= 3) {
      _fail('设备连接已断开，请手动重新连接');
      return;
    }
    _retryCount++;
    link = LinkState.retrying;
    notifyListeners();
    _retryTimer = Timer(Duration(seconds: _retryCount * 2), _open);
  }

  void _onNotice(List<int> value) {
    if (value.isEmpty) return;
    final msg = RuneCodec.notice(value);
    _log(msg.text, msg.type);
    switch (msg.type) {
      case RuneMsgType.start:
        _cmdTimer?.cancel();
        runState = RunState.running;
        break;
      case RuneMsgType.score:
        _cmdTimer?.cancel();
        runState = RunState.running;
        if (msg.score != null) {
          latestScore = msg.score;
          scores = [msg.score!, ...scores].take(10).toList();
        }
        break;
      case RuneMsgType.complete:
        _cmdTimer?.cancel();
        runState = RunState.idle;
        unawaited(
          _read(BleIds.scores).then((value) {
            if (value.isNotEmpty) {
              scores = value;
              notifyListeners();
            }
          }),
        );
        break;
      case RuneMsgType.failed:
      case RuneMsgType.text:
        break;
    }
    notifyListeners();
  }

  BluetoothCharacteristic _need(Guid id) {
    final chr = _chars[id];
    if (chr == null) throw StateError('缺少特征值 $id');
    return chr;
  }

  int _one(List<int> value) => value.isEmpty ? 0 : value.first;

  int _light(Guid id) {
    if (id == BleIds.armourLight) return armourLight;
    if (id == BleIds.edgeLight) return edgeLight;
    if (id == BleIds.logoLight) return logoLight;
    return matrixLight;
  }

  void _setLightValue(Guid id, int value) {
    final safe = value.clamp(0, 255).toInt();
    if (id == BleIds.armourLight) {
      armourLight = safe;
    } else if (id == BleIds.edgeLight) {
      edgeLight = safe;
    } else if (id == BleIds.logoLight) {
      logoLight = safe;
    } else {
      matrixLight = safe;
    }
  }

  void _log(String text, RuneMsgType type) {
    if (text.isEmpty) return;
    logs.insert(0, RuneLog(DateTime.now(), text, type));
    if (logs.length > 100) logs.removeLast();
  }

  void _waitForConfirm(RunState pending, String message) {
    _cmdTimer = Timer(const Duration(seconds: 5), () {
      if (runState != pending) return;
      runState = RunState.unknown;
      _log(message, RuneMsgType.failed);
      notifyListeners();
    });
  }

  void _fail(String message, {bool keepLink = false}) {
    error = message;
    if (!keepLink) link = LinkState.error;
    notifyListeners();
  }

  Future<void> _clearSession() async {
    _cmdTimer?.cancel();
    await _noticeSub?.cancel();
    await _mtuSub?.cancel();
    _noticeSub = null;
    _mtuSub = null;
    _chars.clear();
  }

  @override
  void dispose() {
    _manualOff = true;
    _retryTimer?.cancel();
    _cmdTimer?.cancel();
    _cancelDemoTimers();
    unawaited(_scanSub?.cancel());
    unawaited(_scanStateSub?.cancel());
    unawaited(_linkSub?.cancel());
    unawaited(_clearSession());
    if (FlutterBluePlus.isScanningNow) unawaited(FlutterBluePlus.stopScan());
    super.dispose();
  }
}
