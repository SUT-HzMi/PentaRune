import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/rune_ble.dart';
import 'scan_screen.dart';
import 'tabs/config_tab.dart';
import 'tabs/control_tab.dart';
import 'tabs/log_tab.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final RuneBle _ble;
  late final PageController _pages;
  int _tab = 0;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _pages = PageController();
    _ble = RuneBle()..addListener(_onBle);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ble.scan());
  }

  @override
  void dispose() {
    _ble.removeListener(_onBle);
    _ble.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _onBle() {
    if (!mounted) return;
    setState(() {});
    final error = _ble.error;
    if (error == null || error == _lastError) return;
    _lastError = error;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PentaRune'),
            Text('赫兹矩阵机器人战队', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: PageView(
            controller: _pages,
            onPageChanged: (value) {
              if (_tab != value) setState(() => _tab = value);
            },
            children: [
              ControlTab(ble: _ble),
              ConfigTab(ble: _ble, onDebug: _openDebug),
              LogTab(ble: _ble),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) {
          setState(() => _tab = value);
          _pages.animateToPage(
            value,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '控制',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune),
            selectedIcon: Icon(Icons.tune),
            label: '设置',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: '日志',
          ),
        ],
      ),
    );
  }

  Future<void> _openDebug() async {
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ScanScreen()));
    if (mounted && !_ble.connected) unawaited(_ble.scan());
  }
}
