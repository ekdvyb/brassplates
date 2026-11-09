import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../services/platform/platform_service.dart';
import '../../widgets/common.dart';

final _snapshotsProvider = FutureProvider.autoDispose<List<Snapshot>>(
  (ref) => ref.watch(snapshotServiceProvider).list(),
);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _localPath = TextEditingController();
  SyncProviderKind _syncKind = SyncProviderKind.none;
  bool _loadedSync = false;
  bool _savingSync = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _loadSync();
  }

  @override
  void dispose() {
    _localPath.dispose();
    super.dispose();
  }

  Future<void> _loadSync() async {
    final settings = ref.read(settingsRepositoryProvider);
    final raw = await settings.get('sync.provider') ?? 'none';
    final kind = SyncProviderKind.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => SyncProviderKind.none,
    );
    final path = await settings.get('sync.local.path') ?? '';
    if (!mounted) return;
    setState(() {
      _syncKind = kind;
      _localPath.text = path;
      _loadedSync = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final vault = ref.watch(vaultProvider);
    final snapshots = ref.watch(_snapshotsProvider);
    final syncStatus = ref.watch(syncStatusProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        const SectionHeader(
          title: 'Settings',
          subtitle: 'Notes and tasks. Everything is stored locally.',
        ),
        const SizedBox(height: 18),
        _Section(
          title: 'Appearance',
          icon: Icons.palette_outlined,
          children: [
            const _Label('Theme'),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Dark'),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (selection) => ref
                  .read(appSettingsProvider.notifier)
                  .setTheme(selection.first),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const SizedBox(width: 120, child: Text('Text size')),
                Expanded(
                  child: Slider(
                    value: settings.fontScale,
                    min: 0.85,
                    max: 1.35,
                    divisions: 10,
                    label: '${(settings.fontScale * 100).round()}%',
                    onChanged: (value) => ref
                        .read(appSettingsProvider.notifier)
                        .setFontScale(value),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${(settings.fontScale * 100).round()}%',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Vault & security',
          icon: Icons.shield_outlined,
          children: [
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                vault.unlocked ? Icons.lock_open : Icons.lock,
                color: BrandColors.success,
              ),
              title: Text(
                vault.unlocked ? 'Vault is unlocked' : 'Vault is locked',
              ),
              subtitle: const Text(
                'AES-256-GCM · Argon2id key derivation · local only',
              ),
              trailing: OutlinedButton(
                onPressed: () => ref.read(vaultProvider.notifier).lock(),
                child: const Text('Lock now'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 140, child: Text('Auto-lock after')),
                const SizedBox(width: 10),
                DropdownButton<int>(
                  value: settings.autoLockMinutes,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Never')),
                    DropdownMenuItem(value: 1, child: Text('1 minute')),
                    DropdownMenuItem(value: 5, child: Text('5 minutes')),
                    DropdownMenuItem(value: 10, child: Text('10 minutes')),
                    DropdownMenuItem(value: 15, child: Text('15 minutes')),
                    DropdownMenuItem(value: 30, child: Text('30 minutes')),
                    DropdownMenuItem(value: 60, child: Text('1 hour')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setAutoLockMinutes(value);
                    }
                  },
                ),
              ],
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Biometric lock support'),
              subtitle: const Text('Use device biometrics where available'),
              value: settings.biometricLock,
              onChanged: (value) async {
                final platform = PlatformService.instance;
                if (value) {
                  final available = await platform.biometricsAvailable();
                  if (!available) {
                    if (!context.mounted) return;
                    showAppSnack(
                      context,
                      'Biometrics are not available on this device.',
                      error: true,
                    );
                    return;
                  }
                  final ok = await platform.authenticate(
                    'Enable biometric lock for BRASSPLATES',
                  );
                  if (!ok) return;
                }
                await ref
                    .read(appSettingsProvider.notifier)
                    .setBiometricLock(value);
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _changePassword,
                  icon: const Icon(Icons.password_outlined, size: 16),
                  label: const Text('Change password'),
                ),
                OutlinedButton.icon(
                  onPressed: _showRecoveryKey,
                  icon: const Icon(Icons.key_outlined, size: 16),
                  label: const Text('Show recovery key'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Sync between devices',
          icon: Icons.sync_outlined,
          children: [
            Text(
              'Choose a folder that is already synced by a service you trust — '
              'Google Drive, OneDrive, Dropbox, Syncthing or a network share. '
              'BRASSPLATES writes only encrypted files there, so the provider '
              'never sees your notes. Point your phone and laptop at the same '
              'folder to keep them together.',
              style: context.theme.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 12),
            if (!_loadedSync)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Row(
                children: [
                  const SizedBox(width: 110, child: Text('Sync')),
                  const SizedBox(width: 10),
                  DropdownButton<SyncProviderKind>(
                    value: _syncKind,
                    items: const [
                      DropdownMenuItem(
                        value: SyncProviderKind.none,
                        child: Text('Off'),
                      ),
                      DropdownMenuItem(
                        value: SyncProviderKind.localFolder,
                        child: Text('Synced folder'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _syncKind = value ?? _syncKind),
                  ),
                ],
              ),
              if (_syncKind == SyncProviderKind.localFolder) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _localPath,
                        decoration: const InputDecoration(
                          labelText: 'Sync folder',
                          hintText: 'e.g. ~/Google Drive/BRASSPLATES',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        final dir = await FilePicker.getDirectoryPath();
                        if (dir != null) {
                          setState(() => _localPath.text = dir);
                        }
                      },
                      child: const Text('Choose'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Tip: create a BRASSPLATES folder inside your cloud folder on '
                  'both devices. Large pictures are included.',
                  style: context.theme.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _savingSync ? null : _saveSync,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Save sync settings'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _testSync,
                    icon: _testing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.folder_open, size: 16),
                    label: const Text('Test folder'),
                  ),
                  OutlinedButton.icon(
                    onPressed: syncStatus.syncing
                        ? null
                        : () => ref.read(syncStatusProvider.notifier).run(),
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('Sync now'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                syncStatus.error != null
                    ? 'Last attempt failed: ${syncStatus.error}'
                    : syncStatus.lastSync == null
                    ? 'Never synced. Pending changes: ${syncStatus.pending}'
                    : 'Last sync ${timeAgo(syncStatus.lastSync)} · pending ${syncStatus.pending}',
                style: context.theme.textTheme.bodySmall?.copyWith(
                  color: syncStatus.error != null
                      ? BrandColors.danger
                      : context.colors.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Backup & recovery',
          icon: Icons.backup_outlined,
          children: [
            Text(
              'An encrypted backup contains your notes, tasks and pictures. '
              'Save it to your cloud folder, a USB drive or send it to yourself.',
              style: context.theme.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _exportEncrypted,
                  icon: const Icon(Icons.lock_outline, size: 16),
                  label: const Text('Export encrypted backup'),
                ),
                OutlinedButton.icon(
                  onPressed: _importBackup,
                  icon: const Icon(Icons.upload_outlined, size: 16),
                  label: const Text('Import backup'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final row = await ref
                        .read(snapshotServiceProvider)
                        .create('manual');
                    ref.invalidate(_snapshotsProvider);
                    if (!context.mounted) return;
                    showAppSnack(
                      context,
                      'Snapshot created (${_bytes(row.bytes)}).',
                    );
                  },
                  icon: const Icon(Icons.camera_outlined, size: 16),
                  label: const Text('Snapshot now'),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              'Local snapshots',
              style: context.theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            snapshots.when(
              data: (rows) => rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No snapshots yet.',
                        style: TextStyle(fontSize: 11),
                      ),
                    )
                  : Column(
                      children: [
                        for (final snapshot in rows)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.camera_outlined,
                              size: 18,
                            ),
                            title: Text(
                              '${snapshot.reason} · ${formatDateTime(snapshot.createdAt)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            subtitle: Text(
                              _bytes(snapshot.bytes),
                              style: const TextStyle(fontSize: 10),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Restore snapshot',
                                  onPressed: () => _restoreSnapshot(snapshot),
                                  icon: const Icon(Icons.restore, size: 18),
                                ),
                                IconButton(
                                  tooltip: 'Delete snapshot',
                                  onPressed: () async {
                                    await ref
                                        .read(snapshotServiceProvider)
                                        .deleteSnapshot(snapshot);
                                    ref.invalidate(_snapshotsProvider);
                                  },
                                  icon: const Icon(Icons.close, size: 16),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Text(error.toString()),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Desktop & startup',
          icon: Icons.desktop_windows_outlined,
          children: [
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Launch at startup'),
              value: settings.launchAtStartup,
              onChanged: (value) async {
                await ref
                    .read(appSettingsProvider.notifier)
                    .setLaunchAtStartup(value);
                await PlatformService.instance.setStartup(value);
              },
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Minimize to tray'),
              value: settings.minimizeToTray,
              onChanged: (value) => ref
                  .read(appSettingsProvider.notifier)
                  .setMinimizeToTray(value),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Global shortcut: Ctrl+Shift+B to bring BRASSPLATES to the front.',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Maintenance',
          icon: Icons.build_outlined,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _integrityCheck,
                  icon: const Icon(Icons.health_and_safety_outlined, size: 16),
                  label: const Text('Integrity check'),
                ),
                OutlinedButton.icon(
                  onPressed: _rebuildSearch,
                  icon: const Icon(Icons.manage_search, size: 16),
                  label: const Text('Rebuild search index'),
                ),
                OutlinedButton.icon(
                  onPressed: _purgeTrash,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                  label: const Text('Purge trash older than 30 days'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'About',
          icon: Icons.info_outline,
          children: [
            const BrandMark(size: 40),
            const SizedBox(height: 10),
            Text('${AppInfo.name} ${AppInfo.version}'),
            const SizedBox(height: 4),
            Text(
              AppInfo.description,
              style: context.theme.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: AppInfo.name,
              ),
              icon: const Icon(Icons.article_outlined, size: 16),
              label: const Text('Open source licenses'),
            ),
          ],
        ),
      ],
    );
  }

  String _bytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change vault password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New password (min 8 characters)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (next.text.length < 8 || next.text != confirm.text) {
      if (mounted) {
        showAppSnack(
          context,
          'New passwords must match and be 8+ characters.',
          error: true,
        );
      }
      return;
    }
    try {
      await ref
          .read(vaultServiceProvider)
          .changePassword(current.text, next.text);
      if (mounted) showAppSnack(context, 'Vault password updated.');
    } catch (error) {
      if (mounted) {
        showAppSnack(context, 'Could not change password: $error', error: true);
      }
    }
  }

  Future<void> _showRecoveryKey() async {
    try {
      final key = await ref.read(vaultServiceProvider).exportRecoveryKey();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Recovery key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Anyone with this key can unlock your vault. Store it offline.',
              ),
              const SizedBox(height: 12),
              SelectableText(
                key,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: key));
                if (context.mounted) {
                  Navigator.pop(context);
                  showAppSnack(context, 'Recovery key copied.');
                }
              },
              child: const Text('Copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        showAppSnack(
          context,
          'Could not export recovery key: $error',
          error: true,
        );
      }
    }
  }

  Future<void> _saveSync() async {
    final path = _localPath.text.trim();
    if (_syncKind == SyncProviderKind.localFolder && path.isEmpty) {
      showAppSnack(context, 'Choose a sync folder first.', error: true);
      return;
    }
    setState(() => _savingSync = true);
    final settings = ref.read(settingsRepositoryProvider);
    try {
      await settings.set('sync.provider', _syncKind.name);
      await settings.set('sync.local.path', path);
      ref.invalidate(syncServiceProvider);
      await ref.read(syncStatusProvider.notifier).refresh();
      if (mounted) showAppSnack(context, 'Sync settings saved.');
    } catch (error) {
      if (mounted) {
        showAppSnack(
          context,
          'Could not save sync settings: $error',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _savingSync = false);
    }
  }

  Future<void> _testSync() async {
    setState(() => _testing = true);
    try {
      final service = await ref.read(syncServiceProvider.future);
      final ok = await service.provider.test();
      if (mounted) {
        showAppSnack(
          context,
          ok
              ? 'Sync folder is writable.'
              : 'Could not write to that folder. Check the path and permissions.',
          error: !ok,
        );
      }
    } catch (error) {
      if (mounted) {
        showAppSnack(context, 'Folder check failed: $error', error: true);
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _exportEncrypted() async {
    try {
      final bytes = await ref
          .read(backupServiceProvider)
          .exportBytes(encrypt: true);
      final path = await FilePicker.saveFile(
        dialogTitle: 'Export encrypted backup',
        fileName:
            'brassplates-backup-${DateTime.now().toIso8601String().split('T').first}.bpbackup',
        bytes: Uint8List.fromList(bytes),
      );
      if (path == null) return;
      // Also drop a copy in the sync folder when one is configured.
      await _copyToSyncFolder(bytes);
      if (mounted) {
        showAppSnack(context, 'Encrypted backup exported.');
      }
    } catch (error) {
      if (mounted) {
        showAppSnack(context, 'Export failed: $error', error: true);
      }
    }
  }

  Future<void> _copyToSyncFolder(List<int> bytes) async {
    try {
      if (_syncKind != SyncProviderKind.localFolder) return;
      final path = _localPath.text.trim();
      if (path.isEmpty) return;
      final dir = Directory('$path${Platform.pathSeparator}backups');
      await dir.create(recursive: true);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      await File(
        '${dir.path}${Platform.pathSeparator}brassplates-$stamp.bpbackup',
      ).writeAsBytes(bytes, flush: true);
    } catch (_) {
      // The manual export already succeeded; the extra copy is best effort.
    }
  }

  Future<void> _importBackup() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Import BRASSPLATES backup',
    );
    if (picked.isEmpty) return;
    final bytes = await picked.single.readAsBytes();
    if (!mounted) return;
    final merge = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import backup'),
        content: const Text(
          'Merge keeps existing records and adds the backup. Replace clears local data first (a snapshot is taken automatically).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Replace'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (merge == null) return;
    if (!mounted) return;
    final password = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup password'),
        content: TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password (leave empty for vault-key backups)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    try {
      final count = await ref
          .read(backupServiceProvider)
          .importBytes(
            bytes,
            merge: merge,
            password: password.text.trim().isEmpty
                ? null
                : password.text.trim(),
          );
      ref.invalidate(_snapshotsProvider);
      if (mounted) {
        showAppSnack(context, 'Imported $count records.');
      }
    } catch (error) {
      if (mounted) {
        showAppSnack(context, 'Import failed: $error', error: true);
      }
    }
  }

  Future<void> _restoreSnapshot(Snapshot snapshot) async {
    final ok = await confirmDialog(
      context,
      title: 'Restore this snapshot?',
      message:
          'The current database will be replaced by the snapshot from ${formatDateTime(snapshot.createdAt)}. The app must be restarted afterwards.',
      confirmLabel: 'Restore snapshot',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(snapshotServiceProvider).restore(snapshot);
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Snapshot restored'),
            content: const Text(
              'Close and reopen BRASSPLATES to load the restored database.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        showAppSnack(context, 'Restore failed: $error', error: true);
      }
    }
  }

  Future<void> _integrityCheck() async {
    try {
      final result = await ref.read(databaseProvider).integrityCheck();
      if (mounted) {
        showAppSnack(
          context,
          'Database integrity: $result',
          error: result.toLowerCase() != 'ok',
        );
      }
    } catch (error) {
      if (mounted) {
        showAppSnack(context, 'Integrity check failed: $error', error: true);
      }
    }
  }

  Future<void> _rebuildSearch() async {
    try {
      await ref.read(searchServiceProvider).rebuild();
      if (mounted) showAppSnack(context, 'Search index rebuilt.');
    } catch (error) {
      if (mounted) {
        showAppSnack(context, 'Could not rebuild search: $error', error: true);
      }
    }
  }

  Future<void> _purgeTrash() async {
    final ok = await confirmDialog(
      context,
      title: 'Purge old trash?',
      message:
          'Items deleted more than 30 days ago will be permanently removed. This cannot be undone.',
      confirmLabel: 'Purge',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(databaseProvider).purgeExpiredTrash();
    if (mounted) showAppSnack(context, 'Old trash purged.');
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: BrandColors.brass),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: context.theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: context.theme.textTheme.labelMedium?.copyWith(
          color: context.colors.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
