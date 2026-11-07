import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/db/database.dart';
import 'data/repositories/settings_repository.dart';
import 'services/platform/platform_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _acquireSingleInstanceLock();

  final db = AppDatabase();
  final settings = SettingsRepository(db);
  var deviceId = await settings.get('deviceId');
  if (deviceId == null || deviceId.trim().isEmpty) {
    deviceId = const Uuid().v4();
    await settings.set('deviceId', deviceId);
  }

  try {
    await db.purgeExpiredTrash();
  } catch (_) {}

  unawaitedPlatformInit();

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        settingsRepositoryProvider.overrideWithValue(settings),
        deviceIdProvider.overrideWithValue(deviceId),
      ],
      child: const BrassPlatesApp(),
    ),
  );
}

void unawaitedPlatformInit() {
  PlatformService.instance.initDesktop();
  PlatformService.instance.initNotifications();
}

Future<void> _acquireSingleInstanceLock() async {
  try {
    final dir = await getApplicationSupportDirectory();
    final lockFile = File(p.join(dir.path, 'brassplates.lock'));
    await dir.create(recursive: true);
    final handle = await lockFile.open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
    } on FileSystemException {
      exit(0);
    }
  } catch (_) {
    // Locking is best-effort; continue if the platform does not support it.
  }
}
