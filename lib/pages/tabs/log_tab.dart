import 'package:flutter/material.dart';

import '../../ble/codec.dart';
import '../../ble/rune_ble.dart';
import '../../widgets/panel.dart';

class LogTab extends StatelessWidget {
  const LogTab({super.key, required this.ble});

  final RuneBle ble;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: ble.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          RunePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('运行日志'),
                const SizedBox(height: 8),
                if (ble.logs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('暂无运行消息'),
                  )
                else
                  ...ble.logs.map(
                    (log) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        _icon(log.type),
                        color: _color(context, log.type),
                      ),
                      title: Text(log.text),
                      subtitle: Text(_time(log.time)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _icon(RuneMsgType type) => switch (type) {
    RuneMsgType.start => Icons.play_circle_outline,
    RuneMsgType.score => Icons.bolt,
    RuneMsgType.failed => Icons.error_outline,
    RuneMsgType.complete => Icons.check_circle_outline,
    RuneMsgType.text => Icons.notes,
  };

  Color _color(BuildContext context, RuneMsgType type) {
    final scheme = Theme.of(context).colorScheme;
    return switch (type) {
      RuneMsgType.failed => scheme.error,
      RuneMsgType.score => scheme.tertiary,
      RuneMsgType.complete => scheme.primary,
      RuneMsgType.start || RuneMsgType.text => scheme.onSurfaceVariant,
    };
  }

  String _time(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
