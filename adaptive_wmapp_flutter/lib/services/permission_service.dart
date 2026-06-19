import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

/// Handles first-launch permission requests for ACDMT.
///
/// On the first ever launch a dialog explains why permissions are needed,
/// then all required permissions are requested.  On subsequent launches
/// only Bluetooth permissions are re-requested (they may have been revoked).
class PermissionService {
  static const _key = 'permissions_requested_v1';

  static Future<bool> _wasRequested() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/perm_state.json');
      if (!await f.exists()) return false;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return m[_key] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _markRequested() async {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/perm_state.json');
    await f.writeAsString(jsonEncode({_key: true}), flush: true);
  }

  /// Call from [SetupScreen]'s `initState` post-frame callback.
  ///
  /// On first launch shows an explanatory dialog then requests all required
  /// permissions.  On subsequent launches silently re-requests Bluetooth
  /// permissions only (which the user may have revoked in system settings).
  static Future<void> ensurePermissionsOnFirstLaunch(
      BuildContext context) async {
    if (await _wasRequested()) {
      // Already completed first-launch flow – just silently refresh BT perms.
      await _requestBluetooth();
      return;
    }

    if (context.mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Permissions Required'),
          content: const Text(
            'ACDMT needs Bluetooth access to connect to EEG devices and '
            'storage access to save EDF recordings.\n\n'
            'Please grant the requested permissions.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }

    await _requestAll();
    await _markRequested();
  }

  static Future<void> _requestBluetooth() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  static Future<void> _requestAll() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    if (Platform.isAndroid) {
      if (!await Permission.manageExternalStorage.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    }
  }
}
