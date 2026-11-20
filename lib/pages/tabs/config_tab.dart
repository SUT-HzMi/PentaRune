import 'package:flutter/material.dart';

import '../../ble/codec.dart';
import '../../ble/ids.dart';
import '../../ble/rune_ble.dart';
import '../../widgets/panel.dart';

class ConfigTab extends StatelessWidget {
  const ConfigTab({super.key, required this.ble, required this.onDebug});

  final RuneBle ble;
  final VoidCallback onDebug;

  @override
  Widget build(BuildContext context) {
    final enabled = ble.ready;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Opacity(
          opacity: enabled ? 1 : 0.45,
          child: RunePanel(
            child: Column(
              children: [
                SectionTitle(
                  '灯光',
                  action: IconButton(
                    tooltip: '重新读取',
                    onPressed: enabled ? ble.refresh : null,
                    icon: const Icon(Icons.refresh),
                  ),
                ),
                LightTile(
                  icon: Icons.grid_view,
                  label: '装甲板',
                  value: ble.armourLight,
                  enabled: enabled,
                  onSet: (value) => ble.setLight(BleIds.armourLight, value),
                ),
                LightTile(
                  icon: Icons.flare_outlined,
                  label: '靶臂与边缘',
                  value: ble.edgeLight,
                  enabled: enabled,
                  onSet: (value) => ble.setLight(BleIds.edgeLight, value),
                ),
                LightTile(
                  icon: Icons.blur_on,
                  label: '流水灯与矩阵',
                  value: ble.matrixLight,
                  enabled: enabled,
                  onSet: (value) => ble.setLight(BleIds.matrixLight, value),
                ),
                LightTile(
                  icon: Icons.adjust,
                  label: 'RLogo',
                  value: ble.logoLight,
                  enabled: enabled,
                  onSet: (value) => ble.setLight(BleIds.logoLight, value),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Opacity(
          opacity: enabled ? 1 : 0.45,
          child: RunePanel(
            child: PidEditor(ble: ble, enabled: enabled),
          ),
        ),
        const SizedBox(height: 12),
        Opacity(
          opacity: enabled ? 1 : 0.45,
          child: RunePanel(
            child: _BoardTools(ble: ble, enabled: enabled),
          ),
        ),
        const SizedBox(height: 12),
        Opacity(
          opacity: enabled ? 1 : 0.45,
          child: RunePanel(
            child: _Maintenance(ble: ble, enabled: enabled),
          ),
        ),
        const SizedBox(height: 12),
        RunePanel(
          child: _DevOptions(ble: ble, onDebug: onDebug),
        ),
      ],
    );
  }
}

class _BoardTools extends StatelessWidget {
  const _BoardTools({required this.ble, required this.enabled});

  final RuneBle ble;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget indicator(String label, bool online) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          size: 11,
          color: online ? scheme.tertiary : scheme.outline,
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('板卡状态'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (var i = 0; i < 5; i++)
              indicator('装甲${i + 1}', ble.boardStatus & (1 << i) != 0),
            indicator('电机板', ble.boardStatus & (1 << 5) != 0),
          ],
        ),
        const SizedBox(height: 18),
        const SectionTitle('装甲板调试'),
        const SizedBox(height: 6),
        for (var i = 0; i < 5; i++)
          _BoardDebugRow(ble: ble, board: i, enabled: enabled),
        const SizedBox(height: 8),
        _MotorSpeedControl(ble: ble, enabled: enabled),
      ],
    );
  }
}

class _BoardDebugRow extends StatelessWidget {
  const _BoardDebugRow({
    required this.ble,
    required this.board,
    required this.enabled,
  });

  final RuneBle ble;
  final int board;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Future<void> send(int command) async {
      try {
        await ble.sendBoardDebug(command, board);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }

    Widget action(String label, int command) => Tooltip(
      message: label,
      child: OutlinedButton(
        onPressed: enabled ? () => send(command) : null,
        child: Text(label),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 40),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Text(
            '装甲板 ${board + 1}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 480 ? 2 : 4;
            final spacing = 8.0;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            final actions = [
              action('点亮靶心', 1),
              action('整面点亮', 4),
              action('按键测试', 5),
              action('熄灭灯光', 2),
            ];
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final item in actions) SizedBox(width: width, child: item),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MotorSpeedControl extends StatefulWidget {
  const _MotorSpeedControl({required this.ble, required this.enabled});

  final RuneBle ble;
  final bool enabled;

  @override
  State<_MotorSpeedControl> createState() => _MotorSpeedControlState();
}

class _MotorSpeedControlState extends State<_MotorSpeedControl> {
  final _rpm = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _rpm.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final value = double.tryParse(_rpm.text.trim());
    if (value == null || !value.isFinite) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效的目标转速')));
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.ble.setMotorSpeed(value);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('目标转速已发送')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(child: Text('电机目标转速 (rpm)')),
      SizedBox(
        width: 120,
        child: TextField(
          controller: _rpm,
          enabled: widget.enabled && !_sending,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: const InputDecoration(hintText: '例如 10', isDense: true),
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filled(
        tooltip: '发送转速',
        onPressed: widget.enabled && !_sending ? _send : null,
        icon: _sending
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send),
      ),
    ],
  );
}

class LightTile extends StatefulWidget {
  const LightTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onSet,
  });

  final IconData icon;
  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int> onSet;

  @override
  State<LightTile> createState() => _LightTileState();
}

class _LightTileState extends State<LightTile> {
  late double _value;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _value = widget.value.toDouble();
  }

  @override
  void didUpdateWidget(covariant LightTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && widget.value != oldWidget.value) {
      _value = widget.value.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(widget.icon),
          const SizedBox(width: 12),
          SizedBox(width: 92, child: Text(widget.label)),
          Expanded(
            child: Slider(
              min: 0,
              max: 255,
              divisions: 255,
              value: _value,
              label: _value.round().toString(),
              onChangeStart: widget.enabled ? (_) => _dragging = true : null,
              onChanged: widget.enabled
                  ? (value) => setState(() => _value = value)
                  : null,
              onChangeEnd: widget.enabled
                  ? (value) {
                      _dragging = false;
                      widget.onSet(value.round());
                    }
                  : null,
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              _value.round().toString(),
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PidEditor extends StatefulWidget {
  const PidEditor({super.key, required this.ble, required this.enabled});

  final RuneBle ble;
  final bool enabled;

  @override
  State<PidEditor> createState() => _PidEditorState();
}

class _PidEditorState extends State<PidEditor> {
  static const _names = ['Kp', 'Ki', 'Kd', 'I max', 'D max', 'Out max'];
  final _form = GlobalKey<FormState>();
  late final List<TextEditingController> _fields;
  late final List<FocusNode> _focus;
  String _last = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fields = List.generate(6, (_) => TextEditingController());
    _focus = List.generate(6, (_) => FocusNode());
    widget.ble.addListener(_sync);
    _sync(force: true);
  }

  @override
  void dispose() {
    widget.ble.removeListener(_sync);
    for (final field in _fields) {
      field.dispose();
    }
    for (final focus in _focus) {
      focus.dispose();
    }
    super.dispose();
  }

  void _sync({bool force = false}) {
    final key = widget.ble.pid.values.join('|');
    if (!force && (key == _last || _focus.any((node) => node.hasFocus))) return;
    _last = key;
    for (var i = 0; i < _fields.length; i++) {
      _fields[i].text = _num(widget.ble.pid.values[i]);
    }
  }

  String _num(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsPrecision(7);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('电机 PID'),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, box) {
              final width = box.maxWidth >= 520
                  ? (box.maxWidth - 20) / 3
                  : (box.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: List.generate(
                  _fields.length,
                  (i) => SizedBox(
                    width: width,
                    child: TextFormField(
                      enabled: widget.enabled,
                      controller: _fields[i],
                      focusNode: _focus[i],
                      decoration: InputDecoration(labelText: _names[i]),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      validator: (value) {
                        final number = double.tryParse(value ?? '');
                        return number == null || !number.isFinite
                            ? '请输入数字'
                            : null;
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: !widget.enabled || _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('应用 PID'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_form.currentState?.validate() != true) return;
    final values = _fields.map((field) => double.parse(field.text)).toList();
    setState(() => _saving = true);
    try {
      await widget.ble.setPid(
        PidData(
          kp: values[0],
          ki: values[1],
          kd: values[2],
          iMax: values[3],
          dMax: values[4],
          outMax: values[5],
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('PID 参数已发送')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _Maintenance extends StatelessWidget {
  const _Maintenance({required this.ble, required this.enabled});

  final RuneBle ble;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SectionTitle('设备维护'),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_open),
          title: const Text('电机解锁'),
          trailing: const Icon(Icons.chevron_right),
          onTap: enabled
              ? () => _confirm(
                  context,
                  title: '电机解锁',
                  text: '确认设备周围安全后发送解锁命令。',
                  run: ble.unlock,
                )
              : null,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.restart_alt,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('重置装甲板 ID'),
          trailing: const Icon(Icons.chevron_right),
          onTap: enabled
              ? () => _confirm(
                  context,
                  title: '重置装甲板 ID',
                  text: '该操作会立即启动 ID 重置任务。',
                  run: ble.resetId,
                )
              : null,
        ),
      ],
    );
  }

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String text,
    required Future<void> Function() run,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('发送命令'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await run();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$title命令已发送')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

class _DevOptions extends StatelessWidget {
  const _DevOptions({required this.ble, required this.onDebug});

  final RuneBle ble;
  final VoidCallback onDebug;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SectionTitle('杂项'),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.science_outlined),
          title: const Text('演示模式'),
          // subtitle: const Text('本地数据 · 无 BLE 连接'),
          value: ble.demo,
          onChanged: ble.setDemo,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.developer_mode),
          title: const Text('BLE 测试工具'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onDebug,
        ),
      ],
    );
  }
}
