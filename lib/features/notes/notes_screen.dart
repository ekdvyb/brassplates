import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../widgets/common.dart';

final _notesProvider = StreamProvider.autoDispose<List<Note>>(
  (ref) => ref.watch(notesRepositoryProvider).watchActive(),
);

final _noteFoldersProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(libraryRepositoryProvider).watchFolders(),
);

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _folderId;
  bool _grid = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(_notesProvider);
    final folders = ref.watch(_noteFoldersProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Notes',
            subtitle: 'Capture knowledge, decisions and debugging trails.',
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: _grid ? 'List view' : 'Grid view',
                  onPressed: () => setState(() => _grid = !_grid),
                  icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: _createNote,
                  icon: const Icon(Icons.add),
                  label: const Text('New note'),
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
                    hintText: 'Filter notes…',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(width: 12),
              folders.maybeWhen(
                data: (rows) => rows.isEmpty
                    ? const SizedBox.shrink()
                    : SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<String?>(
                          initialValue: _folderId,
                          isDense: true,
                          decoration: const InputDecoration(
                            labelText: 'Folder',
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All folders'),
                            ),
                            for (final folder in rows)
                              DropdownMenuItem<String?>(
                                value: folder.id,
                                child: Text(folder.name),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _folderId = value),
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: notes.when(
              data: (rows) {
                final filtered = rows.where((note) {
                  if (_folderId != null && note.folderId != _folderId) {
                    return false;
                  }
                  if (_query.trim().isEmpty) return true;
                  final needle = _query.toLowerCase();
                  return note.title.toLowerCase().contains(needle) ||
                      note.plainText.toLowerCase().contains(needle) ||
                      note.tagsCsv.toLowerCase().contains(needle);
                }).toList();

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.sticky_note_2_outlined,
                    title: rows.isEmpty ? 'No notes yet' : 'No matches',
                    message: rows.isEmpty
                        ? 'Write down what you just learned. Future you will thank you.'
                        : 'Try a different word or clear the folder filter.',
                    action: rows.isEmpty
                        ? FilledButton.icon(
                            onPressed: _createNote,
                            icon: const Icon(Icons.add),
                            label: const Text('Create a note'),
                          )
                        : null,
                  );
                }

                if (_grid) {
                  return GridView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 340,
                          mainAxisExtent: 170,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) => _NoteCard(
                      note: filtered[index],
                      onDelete: () => _delete(filtered[index]),
                      onPin: () => _togglePin(filtered[index]),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _NoteRow(
                    note: filtered[index],
                    onDelete: () => _delete(filtered[index]),
                    onPin: () => _togglePin(filtered[index]),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Could not load notes',
                message: error.toString(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createNote() async {
    final note = await ref.read(notesRepositoryProvider).create();
    if (mounted) context.go('/notes/${note.id}');
  }

  Future<void> _delete(Note note) async {
    final ok = await confirmDialog(
      context,
      title: 'Move to trash?',
      message: '"${note.title}" can be restored from Trash for 30 days.',
      confirmLabel: 'Move to trash',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(notesRepositoryProvider).softDelete(note.id);
    ref.invalidate(_notesProvider);
  }

  Future<void> _togglePin(Note note) async {
    await ref.read(notesRepositoryProvider).togglePin(note);
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.note,
    required this.onDelete,
    required this.onPin,
  });

  final Note note;
  final VoidCallback onDelete;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    final tags = parseTags(note.tagsCsv);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.go('/notes/${note.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (note.pinned)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.push_pin,
                        size: 15,
                        color: BrandColors.brass,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    timeAgo(note.updatedAt),
                    style: context.theme.textTheme.labelSmall?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Note actions',
                    onSelected: (value) {
                      if (value == 'pin') onPin();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'pin',
                        child: Text(
                          note.pinned ? 'Unpin' : 'Pin',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Move to trash',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (note.plainText.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  truncate(note.plainText.replaceAll(RegExp(r'\s+'), ' '), 170),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    for (final tag in tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: BrandColors.brass.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(tag, style: const TextStyle(fontSize: 10)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.onDelete,
    required this.onPin,
  });

  final Note note;
  final VoidCallback onDelete;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.go('/notes/${note.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (note.pinned)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.push_pin,
                        size: 15,
                        color: BrandColors.brass,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      note.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Note actions',
                    onSelected: (value) {
                      if (value == 'pin') onPin();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'pin',
                        child: Text(
                          note.pinned ? 'Unpin' : 'Pin',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Move to trash',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  note.plainText.trim().isEmpty
                      ? 'Empty note'
                      : truncate(
                          note.plainText.replaceAll(RegExp(r'\s+'), ' '),
                          220,
                        ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
              Text(
                'Updated ${timeAgo(note.updatedAt)}',
                style: context.theme.textTheme.labelSmall?.copyWith(
                  color: context.colors.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
