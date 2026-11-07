import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../widgets/common.dart';

final _serversProvider = StreamProvider.autoDispose<List<ServerEntry>>(
  (ref) => ref.watch(serversRepositoryProvider).watchActive(),
);

class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key});

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
  final _search = TextEditingController();
  String _query = '';
  ServerPurpose? _purpose;
  ServerStatus? _status;
  final Set<String> _checking = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(_serversProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Servers',
            subtitle: 'Inventory, connectivity checks and encrypted credentials in one place.',
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<String>(
                  tooltip: 'Import / export',
                  onSelected: (value) {
                    if (value == 'import') _importCsv();
                    if (value == 'export') _exportCsv();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'import', child: Text('Import CSV')),
                    PopupMenuItem(value: 'export', child: Text('Export CSV')),
                  ],
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: () => _editServer(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add server'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: 'Search by name, IP or database…',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<ServerPurpose?>(
                value: _purpose,
                hint: const Text('Purpose'),
                onChanged: (value) => setState(() => _purpose = value),
                items: [
                  const DropdownMenuItem<ServerPurpose?>(
                    value: null,
                    child: Text('All purposes'),
                  ),
                  for (final purpose in ServerPurpose.values)
                    DropdownMenuItem<ServerPurpose?>(
                      value: purpose,
                      child: Text(purpose.label),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              DropdownButton<ServerStatus?>(
                value: _status,
                hint: const Text('Status'),
                onChanged: (value) => setState(() => _status = value),
                items: [
                  const DropdownMenuItem<ServerStatus?>(
                    value: null,
                    child: Text('All statuses'),
                  ),
                  for (final status in ServerStatus.values)
                    DropdownMenuItem<ServerStatus?>(
                      value: status,
                      child: Text(status.label),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: servers.when(
              data: (rows) {
                final filtered = rows.where((server) {
                  if (_purpose != null && server.purpose != _purpose) {
                    return false;
                  }
                  if (_status != null && server.status != _status) return false;
                  if (_query.trim().isEmpty) return true;
                  final needle = _query.toLowerCase();
                  return server.name.toLowerCase().contains(needle) ||
                      server.ip.toLowerCase().contains(needle) ||
                      server.databaseName.toLowerCase().contains(needle) ||
                      server.notes.toLowerCase().contains(needle);
                }).toList();

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.dns_outlined,
                    title: rows.isEmpty ? 'No servers yet' : 'No matches',
                    message: rows.isEmpty
                        ? 'Add your SQL servers, trading nodes and FDMS hosts. Secrets are encrypted with your vault key.'
                        : 'Try another search or filter.',
                    action: rows.isEmpty
                        ? FilledButton.icon(
                            onPressed: () => _editServer(),
                            icon: const Icon(Icons.add),
                            label: const Text('Add a server'),
                          )
                        : null,
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final server = filtered[index];
                    return _ServerCard(
                      server: server,
                      checking: _checking.contains(server.id),
                      onEdit: () => _editServer(server),
                      onReveal: () => _reveal(server),
                      onCheck: () => _check(server),
                      onDelete: () => _delete(server),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Could not load servers',
                message: error.toString(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _check(ServerEntry server) async {
    setState(() => _checking.add(server.id));
    final result = await ref.read(serversRepositoryProvider).checkTcp(server);
    if (!mounted) return;
    setState(() => _checking.remove(server.id));
    showAppSnack(
      context,
      result == ServerStatus.online
          ? '${server.name} is reachable on port 1433.'
          : '${server.name} did not respond on port 1433.',
      error: result != ServerStatus.online,
    );
  }

  Future<void> _reveal(ServerEntry server) async {
    try {
      final secret = await ref
          .read(serversRepositoryProvider)
          .revealSecret(server);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(server.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Decrypted secret'),
              const SizedBox(height: 10),
              SelectableText(
                secret,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: secret));
                if (context.mounted) {
                  Navigator.pop(context);
                  showAppSnack(context, 'Secret copied.');
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
        showAppSnack(context, 'Could not decrypt: $error', error: true);
      }
    }
  }

  Future<void> _delete(ServerEntry server) async {
    final ok = await confirmDialog(
      context,
      title: 'Move to trash?',
      message: '"${server.name}" can be restored from Trash for 30 days.',
      confirmLabel: 'Move to trash',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(serversRepositoryProvider).softDelete(server.id);
  }

  Future<void> _editServer([ServerEntry? server]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ServerDialog(server: server),
    );
    if (saved == true) ref.invalidate(_serversProvider);
  }

  Future<void> _importCsv() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Import servers from CSV',
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (picked.isEmpty) return;
    final bytes = await picked.single.readAsBytes();
    try {
      final count = await ref
          .read(serversRepositoryProvider)
          .importCsv(utf8.decode(bytes));
      ref.invalidate(_serversProvider);
      if (mounted) showAppSnack(context, 'Imported $count servers.');
    } catch (error) {
      if (mounted) {
        showAppSnack(context, 'Import failed: $error', error: true);
      }
    }
  }

  Future<void> _exportCsv() async {
    try {
      final csv = await ref.read(serversRepositoryProvider).exportCsv();
      await FilePicker.saveFile(
        dialogTitle: 'Export servers',
        fileName: 'brassplates-servers.csv',
        bytes: Uint8List.fromList(utf8.encode(csv)),
      );
      if (mounted) showAppSnack(context, 'CSV exported.');
    } catch (error) {
      if (mounted) showAppSnack(context, 'Export failed: $error', error: true);
    }
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.server,
    required this.checking,
    required this.onEdit,
    required this.onReveal,
    required this.onCheck,
    required this.onDelete,
  });

  final ServerEntry server;
  final bool checking;
  final VoidCallback onEdit;
  final VoidCallback onReveal;
  final VoidCallback onCheck;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (server.status) {
      ServerStatus.online => BrandColors.success,
      ServerStatus.offline => BrandColors.danger,
      ServerStatus.unknown => BrandColors.warning,
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.dns_outlined, color: statusColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          server.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: BrandColors.brass.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          server.purpose.label,
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                      if (server.hasSecret)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.lock_outline,
                            size: 13,
                            color: BrandColors.brass,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    children: [
                      if (server.ip.isNotEmpty)
                        _Meta(icon: Icons.lan_outlined, text: server.ip),
                      if (server.databaseName.isNotEmpty)
                        _Meta(
                          icon: Icons.storage_outlined,
                          text: server.databaseName,
                        ),
                      _Meta(
                        icon: Icons.circle,
                        text: server.status.label,
                        color: statusColor,
                      ),
                      if (server.lastBackup != null)
                        _Meta(
                          icon: Icons.backup_outlined,
                          text: 'Backup ${formatDate(server.lastBackup)}',
                          color: daysUntil(server.lastBackup!) < -7
                              ? BrandColors.danger
                              : null,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (server.hasSecret)
              IconButton(
                tooltip: 'Reveal secret',
                onPressed: onReveal,
                icon: const Icon(Icons.key_outlined, size: 18),
              ),
            IconButton(
              tooltip: 'Check TCP 1433',
              onPressed: checking ? null : onCheck,
              icon: checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check, size: 18),
            ),
            PopupMenuButton<String>(
              tooltip: 'Server actions',
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit server')),
                PopupMenuItem(value: 'delete', child: Text('Move to trash')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 11,
          color: color ?? context.colors.onSurface.withValues(alpha: 0.45),
        ),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: color ?? context.colors.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _ServerDialog extends ConsumerStatefulWidget {
  const _ServerDialog({this.server});

  final ServerEntry? server;

  @override
  ConsumerState<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends ConsumerState<_ServerDialog> {
  late final TextEditingController _name;
  late final TextEditingController _ip;
  late final TextEditingController _database;
  late final TextEditingController _notes;
  late final TextEditingController _secret;
  late ServerPurpose _purpose;
  late ServerStatus _status;
  DateTime? _lastBackup;
  bool _saving = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final server = widget.server;
    _name = TextEditingController(text: server?.name ?? '');
    _ip = TextEditingController(text: server?.ip ?? '');
    _database = TextEditingController(text: server?.databaseName ?? '');
    _notes = TextEditingController(text: server?.notes ?? '');
    _secret = TextEditingController();
    _purpose = server?.purpose ?? ServerPurpose.other;
    _status = server?.status ?? ServerStatus.unknown;
    _lastBackup = server?.lastBackup;
  }

  @override
  void dispose() {
    _name.dispose();
    _ip.dispose();
    _database.dispose();
    _notes.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showAppSnack(context, 'Give the server a name.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(serversRepositoryProvider);
      final server = widget.server;
      if (server == null) {
        await repo.create(
          name: _name.text.trim(),
          ip: _ip.text.trim(),
          databaseName: _database.text.trim(),
          purpose: _purpose,
          status: _status,
          lastBackup: _lastBackup,
          notes: _notes.text.trim(),
          secret: _secret.text.isEmpty ? null : _secret.text,
        );
      } else {
        await repo.save(
          server,
          name: _name.text.trim(),
          ip: _ip.text.trim(),
          databaseName: _database.text.trim(),
          purpose: _purpose,
          status: _status,
          lastBackup: _lastBackup,
          notes: _notes.text.trim(),
          newSecret: _secret.text.isEmpty ? null : _secret.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'Could not save server: $error', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.server == null ? 'Add server' : 'Edit server'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Server name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ip,
                      decoration: const InputDecoration(
                        labelText: 'IP / hostname',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _database,
                      decoration: const InputDecoration(
                        labelText: 'Database',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<ServerPurpose>(
                      initialValue: _purpose,
                      decoration: const InputDecoration(
                        labelText: 'Purpose',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final purpose in ServerPurpose.values)
                          DropdownMenuItem(
                            value: purpose,
                            child: Text(purpose.label),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _purpose = value ?? _purpose),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<ServerStatus>(
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final status in ServerStatus.values)
                          DropdownMenuItem(
                            value: status,
                            child: Text(status.label),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _status = value ?? _status),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _secret,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: widget.server?.hasSecret == true
                      ? 'Replace stored secret (optional)'
                      : 'Secret / password (optional)',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  helperText: 'Encrypted with your vault key.',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _lastBackup ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 3650),
                    ),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _lastBackup = picked);
                },
                icon: const Icon(Icons.backup_outlined, size: 16),
                label: Text(
                  _lastBackup == null
                      ? 'Set last backup date'
                      : 'Last backup ${formatDate(_lastBackup)}',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 3,
                minLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
