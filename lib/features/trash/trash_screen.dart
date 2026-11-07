import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/utils.dart';
import '../../data/repositories/trash_repository.dart';
import '../../widgets/common.dart';

final _trashProvider = FutureProvider.autoDispose<List<TrashItem>>(
  (ref) => ref.watch(trashRepositoryProvider).list(),
);

class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(_trashProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Trash',
            subtitle: 'Deleted items stay here until you remove them. Nothing is lost by accident.',
            action: items.maybeWhen(
              data: (rows) => rows.isEmpty
                  ? null
                  : OutlinedButton.icon(
                      onPressed: () => _empty(context, ref, rows.length),
                      icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                      label: const Text('Empty trash'),
                    ),
              orElse: () => null,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: items.when(
              data: (rows) {
                if (rows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.delete_outline,
                    title: 'Trash is empty',
                    message: 'Deleted notes, how-tos, tasks, projects, servers and diagrams appear here.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = rows[index];
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: Icon(
                          _icon(item.type),
                          color: context.colors.onSurface.withValues(
                            alpha: 0.55,
                          ),
                        ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_label(item.type)} · deleted ${timeAgo(item.deletedAt)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Restore',
                              onPressed: () async {
                                await ref
                                    .read(trashRepositoryProvider)
                                    .restore(item);
                                ref.invalidate(_trashProvider);
                                if (context.mounted) {
                                  showAppSnack(
                                    context,
                                    '${item.title} restored.',
                                  );
                                }
                              },
                              icon: const Icon(Icons.restore, size: 19),
                            ),
                            IconButton(
                              tooltip: 'Delete forever',
                              onPressed: () =>
                                  _deleteForever(context, ref, item),
                              icon: const Icon(
                                Icons.delete_forever,
                                size: 19,
                                color: BrandColors.danger,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Could not load trash',
                message: error.toString(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteForever(
    BuildContext context,
    WidgetRef ref,
    TrashItem item,
  ) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete forever?',
      message:
          '"${item.title}" will be permanently removed. This cannot be undone.',
      confirmLabel: 'Delete forever',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(trashRepositoryProvider).deleteForever(item);
    ref.invalidate(_trashProvider);
  }

  Future<void> _empty(BuildContext context, WidgetRef ref, int count) async {
    final ok = await confirmDialog(
      context,
      title: 'Empty the trash?',
      message:
          '$count items will be permanently deleted. This cannot be undone.',
      confirmLabel: 'Empty trash',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(trashRepositoryProvider).emptyTrash();
    ref.invalidate(_trashProvider);
  }

  String _label(String type) => switch (type) {
    'note' => 'Note',
    'howto' => 'How-To',
    'task' => 'Task',
    'project' => 'Project',
    'server' => 'Server',
    'diagram' => 'Diagram',
    'stencil' => 'Stencil',
    _ => type,
  };

  IconData _icon(String type) => switch (type) {
    'note' => Icons.sticky_note_2_outlined,
    'howto' => Icons.menu_book_outlined,
    'task' => Icons.checklist_rounded,
    'project' => Icons.flag_outlined,
    'server' => Icons.dns_outlined,
    'diagram' => Icons.account_tree_outlined,
    'stencil' => Icons.category_outlined,
    _ => Icons.delete_outline,
  };
}
