import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/shortcut_bindings.dart';

class SettingsService {
  SettingsService({Future<Directory> Function()? supportDirectoryProvider})
    : _supportDirectoryProvider =
          supportDirectoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectoryProvider;

  Future<ShortcutBindings> loadShortcutBindings() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) {
        return ShortcutBindings.defaults();
      }

      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, dynamic>) {
        return ShortcutBindings.defaults();
      }

      return ShortcutBindings.fromJson(raw);
    } catch (_) {
      return ShortcutBindings.defaults();
    }
  }

  Future<void> saveShortcutBindings(ShortcutBindings bindings) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(bindings.toJson()),
    );
  }

  Future<File> _settingsFile() async {
    final directory = await _supportDirectoryProvider();
    return File('${directory.path}/settings.json');
  }
}
