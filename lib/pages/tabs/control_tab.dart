import 'dart:async';

import 'package:flutter/material.dart';

import '../../ble/codec.dart';
import '../../ble/rune_ble.dart';
import '../../widgets/panel.dart';

class ControlTab extends StatelessWidget {
  const ControlTab({super.key, required this.ble});

  final RuneBle ble;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _DevicePanel(ble: ble),
        const SizedBox(height: 12),
        _ActionPanel(ble: ble, enabled: ble.ready),
        const SizedBox(height: 12),
        _ScorePanel(ble: ble, enabled: ble.ready),
        const SizedBox(height: 12),
        _RunPanel(ble: ble, enabled: ble.ready),
      ],
    );
  }
}

class _DevicePanel extends StatelessWidget {
  const _DevicePanel({required this.ble});

  final RuneBle ble;

  String get _status => ble.demo
      ? '模拟设备在线'
      : switch (ble.link) {
          LinkState.idle => '等待连接',
          LinkState.scanning => '正在寻找设备',
          LinkState.connecting => '正在连接',
          LinkState.loading => '正在同步设备',
          LinkState.ready => '设备在线',
          LinkState.retrying => '连接中断，正在重连',
          LinkState.error => '连接异常',
        };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RunePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.hub_outlined,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ble.connected ? ble.name : 'PowerRune',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        StateDot(active: ble.ready),
                        const SizedBox(width: 7),
                        Flexible(child: Text(_status)),
                        if (ble.rssi != null) ...[
                          const SizedBox(width: 8),
                          Text('${ble.rssi} dBm'),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (ble.connected)
                IconButton(
                  tooltip: '断开连接',
                  onPressed: ble.disconnect,
                  icon: const Icon(Icons.link_off),
                ),
            ],
          ),
          if (ble.error != null) ...[
            const SizedBox(height: 12),
            Text(ble.error!, style: TextStyle(color: scheme.error)),
          ],
          if (!ble.connected) ...[
            const SizedBox(height: 16),
            if (ble.found.isEmpty)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: ble.link == LinkState.scanning ? null : ble.scan,
                  icon: ble.link == LinkState.scanning
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar),
                  label: Text(ble.link == LinkState.scanning ? '正在扫描' : '查找设备'),
                ),
              )
            else
              ...ble.found.map(
                (result) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bluetooth),
                  title: const Text('PowerRune'),
                  subtitle: Text('${result.rssi} dBm'),
                  trailing: FilledButton(
                    onPressed: () => ble.connect(result),
                    child: const Text('连接'),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _RunPanel extends StatelessWidget {
  const _RunPanel({required this.ble, required this.enabled});

  final RuneBle ble;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cfg = ble.runCfg;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: RunePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('参数设置'),
            const SizedBox(height: 16),
            _OptionRow(
              label: '阵营',
              child: SegmentedButton<TeamColor>(
                segments: const [
                  ButtonSegment(
                    value: TeamColor.red,
                    label: Text('红方'),
                    icon: Icon(Icons.shield_outlined),
                  ),
                  ButtonSegment(
                    value: TeamColor.blue,
                    label: Text('蓝方'),
                    icon: Icon(Icons.shield),
                  ),
                ],
                selected: {cfg.color},
                onSelectionChanged: enabled
                    ? (value) => ble.setRun(cfg.copyWith(color: value.first))
                    : null,
              ),
            ),
            const SizedBox(height: 14),
            _OptionRow(
              label: '模式',
              child: SegmentedButton<RuneMode>(
                segments: const [
                  ButtonSegment(value: RuneMode.big, label: Text('大符')),
                  ButtonSegment(value: RuneMode.small, label: Text('小符')),
                ],
                selected: {cfg.mode},
                onSelectionChanged: enabled
                    ? (value) => ble.setRun(cfg.copyWith(mode: value.first))
                    : null,
              ),
            ),
            const SizedBox(height: 14),
            _OptionRow(
              label: '方向',
              child: SegmentedButton<SpinDir>(
                segments: const [
                  ButtonSegment(
                    value: SpinDir.clockwise,
                    label: Text('顺时针'),
                    icon: Icon(Icons.rotate_right),
                  ),
                  ButtonSegment(
                    value: SpinDir.counterClockwise,
                    label: Text('逆时针'),
                    icon: Icon(Icons.rotate_left),
                  ),
                ],
                selected: {cfg.dir},
                onSelectionChanged: enabled
                    ? (value) => ble.setRun(cfg.copyWith(dir: value.first))
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('循环运行'),
              secondary: const Icon(Icons.repeat),
              value: cfg.loop,
              onChanged: enabled
                  ? (value) => ble.setRun(cfg.copyWith(loop: value))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: child),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 72, child: Text(label)),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({required this.ble, required this.enabled});

  final RuneBle ble;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: _StartStopButton(ble: ble, enabled: enabled),
    );
  }
}

class _StartStopButton extends StatefulWidget {
  const _StartStopButton({required this.ble, required this.enabled});

  final RuneBle ble;
  final bool enabled;

  @override
  State<_StartStopButton> createState() => _StartStopButtonState();
}

class _StartStopButtonState extends State<_StartStopButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _charge;
  Timer? _armTimer;
  int? _pointer;
  bool _armed = false;
  bool _charging = false;
  bool _fired = false;
  bool _downActive = false;

  bool get _active =>
      widget.ble.runState == RunState.starting ||
      widget.ble.runState == RunState.running ||
      widget.ble.runState == RunState.unknown;

  bool get _stopping => widget.ble.runState == RunState.stopping;

  @override
  void initState() {
    super.initState();
    _charge =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 850),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) _start();
        });
  }

  @override
  void didUpdateWidget(covariant _StartStopButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || widget.ble.runState != RunState.idle) {
      _armTimer?.cancel();
      _armed = false;
      _charging = false;
      _charge.stop();
      if (_charge.value != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _charge.reset();
        });
      }
    }
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    _charge.dispose();
    super.dispose();
  }

  void _arm() {
    if (!widget.enabled || widget.ble.runState != RunState.idle) return;
    _armTimer?.cancel();
    setState(() => _armed = true);
    _armTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted || _charging) return;
      setState(() => _armed = false);
    });
  }

  void _beginCharge() {
    _armTimer?.cancel();
    setState(() => _charging = true);
    _charge.forward(from: 0);
  }

  void _start() {
    if (!widget.enabled || widget.ble.runState != RunState.idle) return;
    _fired = true;
    _armed = false;
    _charging = false;
    unawaited(widget.ble.start());
  }

  void _cancelArm() {
    _armTimer?.cancel();
    _armed = false;
    _charging = false;
    if (_charge.isAnimating || _charge.value != 0) {
      _charge.stop();
      _charge.reset();
    }
  }

  void _onDown(PointerDownEvent event) {
    if (!widget.enabled || _stopping || _pointer != null) return;
    _pointer = event.pointer;
    _downActive = _active;
    if (!_active && _armed) _beginCharge();
  }

  void _onUp(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    if (_fired) {
      _fired = false;
      return;
    }
    if (_downActive || _active) {
      _downActive = false;
      if (!_stopping) unawaited(widget.ble.stop());
      return;
    }
    if (_charging) {
      setState(_cancelArm);
      return;
    }
    _arm();
  }

  void _onCancel(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    _downActive = false;
    if (_charging) setState(_cancelArm);
  }

  String get _state => switch (widget.ble.runState) {
    RunState.idle => '待机',
    RunState.starting => '等待启动确认',
    RunState.running => '运行中',
    RunState.stopping => '正在停止',
    RunState.unknown => '设备状态待确认',
  };

  String get _hint {
    if (!widget.enabled) return '设备未连接';
    if (_stopping) return '正在等待设备确认';
    if (_active) return '停止';
    //if (_charging) return '保持按住 · ${(_charge.value * 100).round()}%';
    if (_charging) return '继续长按以启动';
    if (_armed) return '继续长按以启动';
    return '启动';
  }

  IconData get _icon {
    if (!widget.enabled) return Icons.power_off_rounded;
    if (_charging) return Icons.power_settings_new_rounded;
    // Icons.bolt
    return switch (widget.ble.runState) {
      RunState.idle => Icons.power_settings_new_rounded,
      RunState.starting => Icons.hourglass_top,
      RunState.running => Icons.stop_circle_outlined,
      RunState.stopping => Icons.pending_outlined,
      RunState.unknown => Icons.warning_amber,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _active || _stopping;
    final base = !widget.enabled
        ? scheme.surfaceContainerHighest
        : active
        ? scheme.errorContainer
        : _armed
        ? scheme.secondaryContainer
        : scheme.primaryContainer;
    final foreground = !widget.enabled
        ? scheme.onSurfaceVariant
        : active
        ? scheme.onErrorContainer
        : _armed
        ? scheme.onSecondaryContainer
        : scheme.onPrimaryContainer;

    return AnimatedBuilder(
      animation: _charge,
      builder: (context, _) => Semantics(
        button: true,
        enabled: widget.enabled && !_stopping,
        label: '$_state，$_hint',
        child: MouseRegion(
          cursor: widget.enabled && !_stopping
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (_) {},
            child: Listener(
              onPointerDown: _onDown,
              onPointerUp: _onUp,
              onPointerCancel: _onCancel,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 132,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: base),
                      if (_charging)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: _charge.value,
                            heightFactor: 1,
                            child: ColoredBox(color: scheme.primary),
                          ),
                        ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          child: Row(
                            children: [
                              Icon(
                                _icon,
                                size: 42,
                                color: _charging
                                    ? scheme.onPrimary
                                    : foreground,
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _state,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            color: _charging
                                                ? scheme.onPrimary
                                                : foreground,
                                          ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      _hint,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color:
                                                (_charging
                                                        ? scheme.onPrimary
                                                        : foreground)
                                                    .withValues(alpha: 0.82),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScorePanel extends StatelessWidget {
  const _ScorePanel({required this.ble, required this.enabled});

  final RuneBle ble;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final values = List<int?>.generate(
      10,
      (index) => index < ble.scores.length ? ble.scores[index] : null,
    );
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: RunePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: SectionTitle('成绩记录')),
                if (ble.latestScore != null)
                  Text(
                    '最新 ${ble.latestScore}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                IconButton(
                  tooltip: '清空成绩记录',
                  onPressed: enabled ? ble.clearScores : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, box) {
                final count = box.maxWidth < 420 ? 5 : 10;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 0.88,
                  ),
                  itemCount: values.length,
                  itemBuilder: (context, index) {
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            values[index]?.toString() ?? '—',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '${index + 1}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
