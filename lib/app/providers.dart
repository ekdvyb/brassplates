import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/db/database.dart';
import '../data/models/enums.dart';
import '../data/repositories/attachments_repository.dart';
import '../data/repositories/dashboard_repository.dart';
import '../data/repositories/diagrams_repository.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/notes_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/tasks_repository.dart';
import '../data/repositories/trash_repository.dart';
import '../services/backup/backup_service.dart';
import '../services/crypto/vault_service.dart';
import '../services/search/search_service.dart';
import '../services/snapshot/snapshot_service.dart';
import '../services/sync/sync_provider.dart';
import '../services/platform/platform_service.dart';
import '../services/sync/sync_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('databaseProvider must be overridden in main()');
});

final deviceIdProvider = Provider<String>((ref) => 'unknown-device');

final vaultServiceProvider = Provider<VaultService>((ref) => VaultService());

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

final notesRepositoryProvider = Provider<NotesRepository>(
  (ref) =>
      NotesRepository(ref.watch(databaseProvider), ref.watch(deviceIdProvider)),
);

final tasksRepositoryProvider = Provider<TasksRepository>(
  (ref) =>
      TasksRepository(ref.watch(databaseProvider), ref.watch(deviceIdProvider)),
);

final diagramsRepositoryProvider = Provider<DiagramsRepository>(
  (ref) => DiagramsRepository(
    ref.watch(databaseProvider),
    ref.watch(deviceIdProvider),
  ),
);

final attachmentsRepositoryProvider = Provider<AttachmentsRepository>(
  (ref) => AttachmentsRepository(
    ref.watch(databaseProvider),
    ref.watch(deviceIdProvider),
  ),
);

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(
    ref.watch(databaseProvider),
    ref.watch(deviceIdProvider),
  ),
);

final trashRepositoryProvider = Provider<TrashRepository>(
  (ref) =>
      TrashRepository(ref.watch(databaseProvider), ref.watch(deviceIdProvider)),
);

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(databaseProvider)),
);

final searchServiceProvider = Provider<SearchService>(
  (ref) => SearchService(ref.watch(databaseProvider)),
);

final snapshotServiceProvider = Provider<SnapshotService>(
  (ref) => SnapshotService(ref.watch(databaseProvider)),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    db: ref.watch(databaseProvider),
    vault: ref.watch(vaultServiceProvider),
    snapshots: ref.watch(snapshotServiceProvider),
  ),
);

class VaultState {
  const VaultState({
    this.checking = true,
    this.initialized = false,
    this.unlocked = false,
    this.error,
    this.recoveryKey,
  });

  final bool checking;
  final bool initialized;
  final bool unlocked;
  final String? error;
  final String? recoveryKey;

  VaultState copyWith({
    bool? checking,
    bool? initialized,
    bool? unlocked,
    String? error,
    String? recoveryKey,
  }) => VaultState(
    checking: checking ?? this.checking,
    initialized: initialized ?? this.initialized,
    unlocked: unlocked ?? this.unlocked,
    error: error,
    recoveryKey: recoveryKey ?? this.recoveryKey,
  );
}

class VaultNotifier extends Notifier<VaultState> {
  @override
  VaultState build() {
    _check();
    return const VaultState();
  }

  VaultService get _vault => ref.read(vaultServiceProvider);

  Future<void> _check() async {
    final initialized = await _vault.isInitialized();
    state = VaultState(
      checking: false,
      initialized: initialized,
      unlocked: _vault.isUnlocked,
    );
  }

  Future<bool> setup(String password, {String? hint}) async {
    try {
      await _vault.setup(password, hint: hint);
      await _afterUnlock();
      state = const VaultState(
        checking: false,
        initialized: true,
        unlocked: true,
      );
      return true;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      return false;
    }
  }

  Future<bool> unlock(String password) async {
    final ok = await _vault.unlock(password);
    if (ok) {
      await _afterUnlock();
      state = const VaultState(
        checking: false,
        initialized: true,
        unlocked: true,
      );
    } else {
      state = state.copyWith(error: 'Wrong password. Try again.');
    }
    return ok;
  }

  Future<bool> unlockWithRecovery(String recoveryKey) async {
    final ok = await _vault.unlockWithRecoveryKey(recoveryKey);
    if (ok) {
      await _afterUnlock();
      state = const VaultState(
        checking: false,
        initialized: true,
        unlocked: true,
      );
    } else {
      state = state.copyWith(error: 'That recovery key did not work.');
    }
    return ok;
  }

  Future<void> _afterUnlock() async {
    await ref.read(snapshotServiceProvider).maybeDailySnapshot();
  }

  Future<String?> exportRecoveryKey() async {
    try {
      final key = await _vault.exportRecoveryKey();
      state = state.copyWith(recoveryKey: key);
      return key;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      return null;
    }
  }

  void lock() {
    _vault.lock();
    state = const VaultState(
      checking: false,
      initialized: true,
      unlocked: false,
    );
  }
}

final vaultProvider = NotifierProvider<VaultNotifier, VaultState>(
  VaultNotifier.new,
);

class AppSettingsState {
  const AppSettingsState({
    this.themeMode = ThemeMode.system,
    this.fontScale = 1,
    this.autoLockMinutes = 10,
    this.biometricLock = false,
    this.launchAtStartup = false,
    this.minimizeToTray = false,
    this.canvasDark = false,
  });

  final ThemeMode themeMode;
  final double fontScale;
  final int autoLockMinutes;
  final bool biometricLock;
  final bool launchAtStartup;
  final bool minimizeToTray;
  final bool canvasDark;

  AppSettingsState copyWith({
    ThemeMode? themeMode,
    double? fontScale,
    int? autoLockMinutes,
    bool? biometricLock,
    bool? launchAtStartup,
    bool? minimizeToTray,
    bool? canvasDark,
  }) => AppSettingsState(
    themeMode: themeMode ?? this.themeMode,
    fontScale: fontScale ?? this.fontScale,
    autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
    biometricLock: biometricLock ?? this.biometricLock,
    launchAtStartup: launchAtStartup ?? this.launchAtStartup,
    minimizeToTray: minimizeToTray ?? this.minimizeToTray,
    canvasDark: canvasDark ?? this.canvasDark,
  );
}

class AppSettingsNotifier extends Notifier<AppSettingsState> {
  @override
  AppSettingsState build() {
    _load();
    return const AppSettingsState();
  }

  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  Future<void> _load() async {
    final theme = await _repo.get('theme');
    final scale = await _repo.getDouble('fontScale', fallback: 1);
    final autoLock = await _repo.getInt('autoLockMinutes', fallback: 10);
    final biometric = await _repo.getBool('biometricLock');
    final startup = await _repo.getBool('launchAtStartup');
    final tray = await _repo.getBool('minimizeToTray');
    PlatformService.instance.minimizeToTray = tray;
    final canvasDark = await _repo.getBool('diagramCanvasDark');
    state = AppSettingsState(
      themeMode: switch (theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      fontScale: scale == 0 ? 1 : scale,
      autoLockMinutes: autoLock == 0 ? 10 : autoLock,
      biometricLock: biometric,
      launchAtStartup: startup,
      minimizeToTray: tray,
      canvasDark: canvasDark,
    );
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _repo.set('theme', mode.name);
  }

  Future<void> setFontScale(double value) async {
    state = state.copyWith(fontScale: value);
    await _repo.set('fontScale', value.toString());
  }

  Future<void> setAutoLockMinutes(int value) async {
    state = state.copyWith(autoLockMinutes: value);
    await _repo.set('autoLockMinutes', value.toString());
  }

  Future<void> setBiometricLock(bool value) async {
    state = state.copyWith(biometricLock: value);
    await _repo.set('biometricLock', value.toString());
  }

  Future<void> setLaunchAtStartup(bool value) async {
    state = state.copyWith(launchAtStartup: value);
    await _repo.set('launchAtStartup', value.toString());
  }

  Future<void> setMinimizeToTray(bool value) async {
    state = state.copyWith(minimizeToTray: value);
    PlatformService.instance.minimizeToTray = value;
    await _repo.set('minimizeToTray', value.toString());
  }

  Future<void> setCanvasDark(bool value) async {
    state = state.copyWith(canvasDark: value);
    await _repo.set('diagramCanvasDark', value.toString());
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettingsState>(
      AppSettingsNotifier.new,
    );

class SyncStatusState {
  const SyncStatusState({
    this.lastSync,
    this.pending = 0,
    this.syncing = false,
    this.message,
    this.error,
  });

  final DateTime? lastSync;
  final int pending;
  final bool syncing;
  final String? message;
  final String? error;
}

class SyncStatusNotifier extends Notifier<SyncStatusState> {
  @override
  SyncStatusState build() {
    refresh();
    return const SyncStatusState();
  }

  Future<void> refresh() async {
    final db = ref.read(databaseProvider);
    var pending = 0;
    for (final table in SyncService.entityTables) {
      final row = await db
          .customSelect(
            "SELECT COUNT(*) c FROM \"$table\" WHERE sync_status = 'pending'",
          )
          .getSingle();
      pending += (row.data['c'] as int?) ?? 0;
    }
    final last = await ref
        .read(settingsRepositoryProvider)
        .get('sync.lastSync');
    state = SyncStatusState(
      lastSync: DateTime.tryParse(last ?? ''),
      pending: pending,
      syncing: state.syncing,
      message: state.message,
      error: state.error,
    );
  }

  Future<void> run() async {
    final kind =
        await ref.read(settingsRepositoryProvider).get('sync.provider') ??
        'none';
    if (kind != SyncProviderKind.localFolder.name) {
      state = SyncStatusState(
        lastSync: state.lastSync,
        pending: state.pending,
        message: 'Choose a sync folder in Settings first.',
      );
      return;
    }
    state = SyncStatusState(
      lastSync: state.lastSync,
      pending: state.pending,
      syncing: true,
      message: 'Syncing…',
    );
    try {
      final service = await ref.read(syncServiceProvider.future);
      final result = await service.sync();
      final stamp = DateTime.now();
      if (result.ok) {
        await ref
            .read(settingsRepositoryProvider)
            .set('sync.lastSync', stamp.toIso8601String());
        await refresh();
        state = SyncStatusState(
          lastSync: stamp,
          pending: 0,
          message:
              'Synced: ${result.pushed} pushed, ${result.pulled} pulled, ${result.conflicts} conflicts.',
        );
      } else {
        await refresh();
        state = SyncStatusState(
          lastSync: state.lastSync,
          pending: state.pending,
          error: result.errors.join('\n'),
        );
      }
    } catch (error) {
      state = SyncStatusState(
        lastSync: state.lastSync,
        pending: state.pending,
        error: error.toString(),
      );
    }
  }
}

final syncStatusProvider =
    NotifierProvider<SyncStatusNotifier, SyncStatusState>(
      SyncStatusNotifier.new,
    );

final syncServiceProvider = FutureProvider<SyncService>((ref) async {
  final settings = ref.watch(settingsRepositoryProvider);
  final vault = ref.watch(vaultServiceProvider);
  final kindRaw = await settings.get('sync.provider') ?? 'none';
  final kind = SyncProviderKind.values.firstWhere(
    (k) => k.name == kindRaw,
    orElse: () => SyncProviderKind.none,
  );

  final SyncProvider provider;
  switch (kind) {
    case SyncProviderKind.none:
      provider = MemorySyncProvider();
    case SyncProviderKind.localFolder:
      var path = await settings.get('sync.local.path');
      if (path == null || path.isEmpty) {
        final dir = await getApplicationSupportDirectory();
        path = p.join(dir.path, 'sync');
      }
      provider = LocalFolderProvider(path);
  }

  return SyncService(
    db: ref.watch(databaseProvider),
    provider: provider,
    vault: vault,
    snapshots: ref.watch(snapshotServiceProvider),
    deviceId: ref.watch(deviceIdProvider),
  );
});


