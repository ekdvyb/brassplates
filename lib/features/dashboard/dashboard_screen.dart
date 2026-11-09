import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../widgets/common.dart';
import '../tasks/tasks_screen.dart';

final _statsProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(dashboardRepositoryProvider).stats(),
);

final _pinnedNotesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(notesRepositoryProvider).pinned(limit: 4),
);

final _recentNotesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(notesRepositoryProvider).recent(limit: 6),
);

final _upcomingTasksProvider = FutureProvider.autoDispose((ref) async {
  final tasks = await ref.watch(tasksRepositoryProvider).openTasks();
  tasks.sort((a, b) {
    final ad = a.dueDate;
    final bd = b.dueDate;
    if (ad == null && bd == null) return a.sortOrder.compareTo(b.sortOrder);
    if (ad == null) return 1;
    if (bd == null) return -1;
    return ad.compareTo(bd);
  });
  return tasks.take(6).toList();
});

final _lastSnapshotProvider = FutureProvider.autoDispose((ref) async {
  final snapshots = await ref.watch(snapshotServiceProvider).list();
  return snapshots.isEmpty ? null : snapshots.first;
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(_statsProvider);
    final pinned = ref.watch(_pinnedNotesProvider);
    final recent = ref.watch(_recentNotesProvider);
    final tasks = ref.watch(_upcomingTasksProvider);
    final snapshot = ref.watch(_lastSnapshotProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_statsProvider);
        ref.invalidate(_pinnedNotesProvider);
        ref.invalidate(_recentNotesProvider);
        ref.invalidate(_upcomingTasksProvider);
        ref.invalidate(_lastSnapshotProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(),
                      style: context.theme.textTheme.bodyLarge?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    Text(
                      'Your notes and tasks',
                      style: context.theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => _newNote(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('New note'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 1100
                  ? 4
                  : constraints.maxWidth > 760
                  ? 4
                  : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              Widget stat(Widget child) =>
                  SizedBox(width: width, child: child);
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  stat(
                    stats.when(
                      data: (value) => StatCard(
                        label: 'Notes',
                        value: '${value.notes}',
                        icon: Icons.sticky_note_2_outlined,
                        onTap: () => context.go('/notes'),
                      ),
                      loading: () => const _StatSkeleton(),
                      error: (_, _) => const _StatSkeleton(label: 'Notes'),
                    ),
                  ),
                  stat(
                    stats.when(
                      data: (value) => StatCard(
                        label: 'Open tasks',
                        value: '${value.openTasks}',
                        icon: Icons.checklist_rounded,
                        color: BrandColors.warning,
                        onTap: () => context.go('/tasks'),
                      ),
                      loading: () => const _StatSkeleton(),
                      error: (_, _) => const _StatSkeleton(label: 'Tasks'),
                    ),
                  ),
                  stat(
                    stats.when(
                      data: (value) => StatCard(
                        label: 'Done',
                        value: '${value.doneTasks}',
                        icon: Icons.task_alt,
                        color: BrandColors.success,
                        onTap: () => context.go('/tasks'),
                      ),
                      loading: () => const _StatSkeleton(),
                      error: (_, _) => const _StatSkeleton(label: 'Done'),
                    ),
                  ),
                  stat(
                    snapshot.when(
                      data: (value) => StatCard(
                        label: value == null
                            ? 'No snapshot yet'
                            : 'Snapshot ${timeAgo(value.createdAt)}',
                        value: stats.value == null
                            ? 'Protected'
                            : '${stats.value!.pictures} pictures',
                        icon: Icons.verified_user_outlined,
                        color: BrandColors.info,
                        onTap: () => context.go('/settings'),
                      ),
                      loading: () => const _StatSkeleton(),
                      error: (_, _) => const _StatSkeleton(label: 'Snapshots'),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          _QuickActions(
            onNewNote: () => _newNote(context, ref),
            onNewTask: () => showTaskEditor(context, ref),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 900;
              final left = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (pinned.value?.isNotEmpty ?? false) ...[
                    _Card(
                      title: 'Pinned',
                      icon: Icons.push_pin_outlined,
                      action: TextButton(
                        onPressed: () => context.go('/notes'),
                        child: const Text('All notes'),
                      ),
                      child: Column(
                        children: [
                          for (final note in pinned.value!)
                            _NoteTile(note: note),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _Card(
                    title: 'Recent notes',
                    icon: Icons.sticky_note_2_outlined,
                    action: TextButton(
                      onPressed: () => context.go('/notes'),
                      child: const Text('All notes'),
                    ),
                    child: recent.when(
                      data: (notes) => notes.isEmpty
                          ? const _EmptyHint(
                              icon: Icons.sticky_note_2_outlined,
                              text: 'No notes yet. Capture your first thought.',
                            )
                          : Column(
                              children: [
                                for (final note in notes) _NoteTile(note: note),
                              ],
                            ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, _) => _EmptyHint(
                        icon: Icons.error_outline,
                        text: error.toString(),
                      ),
                    ),
                  ),
                ],
              );
              final right = _Card(
                title: 'Upcoming tasks',
                icon: Icons.checklist_rounded,
                action: TextButton(
                  onPressed: () => context.go('/tasks'),
                  child: const Text('All tasks'),
                ),
                child: tasks.when(
                  data: (rows) => rows.isEmpty
                      ? const _EmptyHint(
                          icon: Icons.task_alt,
                          text: 'Nothing pending. Enjoy the quiet.',
                        )
                      : Column(
                          children: [
                            for (final task in rows) _TaskTile(task: task),
                          ],
                        ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _EmptyHint(
                    icon: Icons.error_outline,
                    text: error.toString(),
                  ),
                ),
              );

              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [left, const SizedBox(height: 16), right],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: left),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: right),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              'Everything is saved locally. Sync only through your own folder.',
              style: context.theme.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<void> _newNote(BuildContext context, WidgetRef ref) async {
    final note = await ref.read(notesRepositoryProvider).create();
    if (context.mounted) context.go('/notes/${note.id}');
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.icon,
    required this.child,
    this.action,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: BrandColors.brass),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: context.theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 4),
            child,
          ],
        ),
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        note.pinned ? Icons.push_pin : Icons.description_outlined,
        size: 20,
        color: note.pinned ? BrandColors.brass : null,
      ),
      title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        note.plainText.trim().isEmpty
            ? 'Empty note'
            : truncate(note.plainText.replaceAll(RegExp(r'\s+'), ' '), 70),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        timeAgo(note.updatedAt),
        style: context.theme.textTheme.labelSmall?.copyWith(
          color: context.colors.onSurface.withValues(alpha: 0.5),
        ),
      ),
      onTap: () => context.go('/notes/${note.id}'),
      subtitleTextStyle: context.theme.textTheme.bodySmall,
      minLeadingWidth: 20,
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdue =
        task.dueDate != null &&
        task.dueDate!.isBefore(DateTime.now()) &&
        task.status != TaskStatus.done;
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: false,
      onChanged: (_) async {
        await ref
            .read(tasksRepositoryProvider)
            .move(task, TaskStatus.done, task.sortOrder);
        ref.invalidate(_upcomingTasksProvider);
        ref.invalidate(_statsProvider);
      },
      title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        task.dueDate == null
            ? task.priority.label
            : '${task.priority.label} · due ${formatDate(task.dueDate)}',
        style: TextStyle(
          fontSize: 12,
          color: overdue ? BrandColors.danger : null,
        ),
      ),
      secondary: task.priority == TaskPriority.high
          ? const Icon(Icons.priority_high, color: BrandColors.danger, size: 18)
          : null,
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onNewNote, required this.onNewTask});

  final VoidCallback onNewNote;
  final VoidCallback onNewTask;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: onNewNote,
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('New note'),
        ),
        OutlinedButton.icon(
          onPressed: onNewTask,
          icon: const Icon(Icons.add_task),
          label: const Text('New task'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.go('/search'),
          icon: const Icon(Icons.search),
          label: const Text('Search everything'),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(
            icon,
            size: 30,
            color: context.colors.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: context.theme.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatSkeleton extends StatelessWidget {
  const _StatSkeleton({this.label = 'Loading'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.colors.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: context.theme.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
