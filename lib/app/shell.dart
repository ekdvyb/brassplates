import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import '../features/diagrams/diagram_model.dart';
import '../features/tasks/tasks_screen.dart';
import '../widgets/common.dart';
import 'providers.dart';
import 'theme.dart';

class _Destination {
  const _Destination(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

const _destinations = <_Destination>[
  _Destination('/dashboard', 'Home', Icons.home_outlined),
  _Destination('/notes', 'Notes', Icons.sticky_note_2_outlined),
  _Destination('/tasks', 'Tasks', Icons.checklist_rounded),
  _Destination('/diagrams', 'Diagrams', Icons.account_tree_outlined),
  _Destination('/search', 'Search', Icons.search),
  _Destination('/trash', 'Trash', Icons.delete_outline),
  _Destination('/settings', 'Settings', Icons.settings_outlined),
];

const _primaryMobile = <String>[
  '/dashboard',
  '/notes',
  '/tasks',
  '/diagrams',
];

int _selectedIndex(String path) {
  for (var i = 0; i < _destinations.length; i++) {
    if (path == _destinations[i].path ||
        path.startsWith('${_destinations[i].path}/')) {
      return i;
    }
  }
  return 0;
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.currentPath, required this.child});

  final String currentPath;
  final Widget child;

  Future<void> _newNote(BuildContext context, WidgetRef ref) async {
    final note = await ref.read(notesRepositoryProvider).create();
    if (context.mounted) context.go('/notes/${note.id}');
  }

  Future<void> _newDiagram(BuildContext context, WidgetRef ref) async {
    final document = DiagramDocument();
    final row = await ref
        .read(diagramsRepositoryProvider)
        .create(
          title: document.title,
          documentJson: document.toJson(),
          searchText: document.searchableText,
        );
    if (context.mounted) context.go('/diagrams/${row.id}');
  }

  void _newMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: const Text('New note'),
              onTap: () {
                Navigator.pop(context);
                _newNote(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: const Text('New diagram'),
              onTap: () {
                Navigator.pop(context);
                _newDiagram(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_task),
              title: const Text('New task'),
              onTap: () {
                Navigator.pop(context);
                showTaskEditor(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final selected = _selectedIndex(currentPath);

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
          context.go('/search'),
      const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
          _newNote(context, ref),
      const SingleActivator(LogicalKeyboardKey.keyD, control: true): () =>
          _newDiagram(context, ref),
    };

    final body = CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(autofocus: true, child: child),
    );

    if (width >= 900) {
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(selected: selected),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    if (width >= 700) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selected,
              onDestinationSelected: (index) =>
                  context.go(_destinations[index].path),
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: BrandMark(size: 34, showText: false),
              ),
              destinations: [
                for (final destination in _destinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    label: Text(destination.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    final mobileIndex = _primaryMobile.indexOf(currentPath);
    return Scaffold(
      appBar: AppBar(
        title: const BrandMark(size: 28),
        actions: [
          const SyncDot(),
          IconButton(
            tooltip: 'Search (Ctrl+K)',
            icon: const Icon(Icons.search),
            onPressed: () => context.go('/search'),
          ),
          IconButton(
            tooltip: 'New',
            icon: const Icon(Icons.add),
            onPressed: () => _newMenu(context, ref),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) => context.go(value),
            itemBuilder: (context) => [
              for (final destination in _destinations)
                PopupMenuItem(
                  value: destination.path,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(destination.icon),
                    title: Text(destination.label),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: mobileIndex < 0 ? 0 : mobileIndex,
        onDestinationSelected: (index) {
          if (index < _primaryMobile.length) {
            context.go(_primaryMobile[index]);
          } else {
            _newMenu(context, ref);
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.sticky_note_2_outlined),
            label: 'Notes',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_rounded),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_tree_outlined),
            label: 'Diagrams',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            label: 'New',
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.selected});

  final int selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 240,
      color: context.colors.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: BrandMark(size: 38),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: _destinations.length,
                itemBuilder: (context, index) {
                  final destination = _destinations[index];
                  final active = index == selected;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: ListTile(
                      dense: true,
                      selected: active,
                      selectedTileColor: BrandColors.brass.withValues(
                        alpha: 0.16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      leading: Icon(destination.icon, size: 20),
                      title: Text(
                        destination.label,
                        style: TextStyle(
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      onTap: () => context.go(destination.path),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SyncCard(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final note = await ref
                                .read(notesRepositoryProvider)
                                .create();
                            if (context.mounted) {
                              context.go('/notes/${note.id}');
                            }
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Note'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              ref.read(vaultProvider.notifier).lock(),
                          icon: const Icon(Icons.lock_outline, size: 16),
                          label: const Text('Lock'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${AppInfo.name} ${AppInfo.version}',
                    textAlign: TextAlign.center,
                    style: context.theme.textTheme.labelSmall?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SyncCard extends ConsumerWidget {
  const SyncCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final color = status.error != null
        ? BrandColors.danger
        : status.syncing
        ? BrandColors.brass
        : status.pending > 0
        ? BrandColors.warning
        : BrandColors.success;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.sync, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  status.syncing
                      ? 'Syncing…'
                      : status.message ??
                            (status.pending > 0
                                ? '${status.pending} pending'
                                : status.lastSync == null
                                ? 'Not synced yet'
                                : 'Synced ${timeAgo(status.lastSync)}'),
                  style: context.theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (status.error != null)
                  Text(
                    status.error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.theme.textTheme.labelSmall?.copyWith(
                      color: BrandColors.danger,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sync now',
            visualDensity: VisualDensity.compact,
            onPressed: status.syncing
                ? null
                : () => ref.read(syncStatusProvider.notifier).run(),
            icon: const Icon(Icons.sync, size: 18),
          ),
        ],
      ),
    );
  }
}

class SyncDot extends ConsumerStatefulWidget {
  const SyncDot({super.key});

  @override
  ConsumerState<SyncDot> createState() => _SyncDotState();
}

class _SyncDotState extends ConsumerState<SyncDot> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 90), (_) {
      ref.read(syncStatusProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(syncStatusProvider);
    final color = status.error != null
        ? BrandColors.danger
        : status.syncing
        ? BrandColors.brass
        : status.pending > 0
        ? BrandColors.warning
        : BrandColors.success;
    return IconButton(
      tooltip: status.error ?? 'Sync now',
      onPressed: status.syncing
          ? null
          : () => ref.read(syncStatusProvider.notifier).run(),
      icon: Icon(Icons.sync, color: color),
    );
  }
}
