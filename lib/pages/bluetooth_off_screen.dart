import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/snackbar.dart';

class BluetoothOffScreen extends StatelessWidget {
  const BluetoothOffScreen({super.key, this.adapterState});

  final BluetoothAdapterState? adapterState;

  Widget buildBluetoothOffIcon(BuildContext context) {
    return Icon(
      Icons.bluetooth_disabled,
      size: 88,
      color: Theme.of(context).colorScheme.primary,
    );
  }

  Widget buildTitle(BuildContext context) {
    final state = switch (adapterState) {
      BluetoothAdapterState.unknown => '未知',
      BluetoothAdapterState.unavailable => '不可用',
      BluetoothAdapterState.unauthorized => '未授权',
      BluetoothAdapterState.turningOn => '正在开启',
      BluetoothAdapterState.on => '已开启',
      BluetoothAdapterState.turningOff => '正在关闭',
      BluetoothAdapterState.off => '已关闭',
      null => '未知',
    };
    return Text(
      '蓝牙适配器: $state',
      style: Theme.of(context).textTheme.titleMedium,
    );
  }

  Widget buildTurnOnButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: ElevatedButton(
        child: const Text('开启蓝牙'),
        onPressed: () async {
          try {
            if (!kIsWeb && Platform.isAndroid) {
              await FlutterBluePlus.turnOn();
            }
          } catch (e /*, backtrace*/) {
            Snackbar.show(
              ABC.a,
              prettyException("Error Turning On:", e),
              success: false,
            );
            // print("$e");
            // print("backtrace: $backtrace");
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyA,
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              buildBluetoothOffIcon(context),
              const SizedBox(height: 20),
              buildTitle(context),
              if (!kIsWeb && Platform.isAndroid) buildTurnOnButton(context),
            ],
          ),
        ),
      ),
    );
  }
}
