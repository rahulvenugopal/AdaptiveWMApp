import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ConfigSharingService {
  static Future<void> exportConfig(
    BuildContext context,
    String appName,
    Map<String, dynamic> configJson,
  ) async {
    try {
      final jsonStr = const JsonEncoder.withIndent('  ').convert(configJson);
      final dir = await getTemporaryDirectory();
      // Replace spaces to avoid issues
      final sanitizedAppName = appName.replaceAll(' ', '_');
      final file = File('${dir.path}/${sanitizedAppName}_config.json');
      await file.writeAsString(jsonStr, flush: true);

      final result = await Share.shareXFiles(
        [XFile(file.path)],
        subject: '$appName Configuration',
      );
      // We don't check result here as it might be dismissed.
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export: $e')),
        );
      }
    }
  }

  static Future<Map<String, dynamic>?> importConfig(
    BuildContext context,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonStr = await file.readAsString();
        return jsonDecode(jsonStr) as Map<String, dynamic>;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import: $e')),
        );
      }
    }
    return null;
  }
}
