import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../widgets/common.dart';

final _tasksProvider = StreamProvider.autoDispose<List<Task>>(
  (ref) => ref.watch(tasksRepositoryProvider).watchActive(),
);

/// Opens the task editor. Shared by the Tasks screen, the sidebar and the
/// dashboard so "new task" works from anywhere.
Future<void> showTaskEditor(
  BuildContext context,
  WidgetRef ref, {
  Task? task,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => _TaskFormDialog(task: task),
  );
  if (saved == true) ref.invalidate(_tasksProvider);
}

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  final _search = TextEditingController();
  String _query = '';
  TaskPriority? _priority;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(_tasksProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Tasks',
            subtitle: 'Drag cards between columns. Every move is saved.',
            action: FilledButton.icon(
              onPressed: () => _editTask(),
              icon: const Icon(Icons.add),
              label: const Text('New task'),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: 'Filter tasks…',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<TaskPriority?>(
                value: _priority,
                hint: const Text('Priority'),
                onChanged: (value) => setState(() => _priority = value),
                items: [
                  const DropdownMenuItem<TaskPriority?>(
                    value: null,
                    child: Text('All priorities'),
                  ),
                  for (final priority in TaskPriority.values)
                    DropdownMenuItem<TaskPriority?>(
                      value: priority,
                      child: Text(priority.label),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: tasks.when(
              data: (rows) {
                final filtered = rows.where((task) {
                  if (_priority != null && task.priority != _priority) {
                    return false;
                  }
                  if (_query.trim().isEmpty) return true;
                  final needle = _query.toLowerCase();
                  return task.title.toLowerCase().contains(needle) ||
                      task.description.toLowerCase().contains(needle) ||
                      task.tagsCsv.toLowerCase().contains(needle);
                }).toList();

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 900;
                    final columnWidth = wide
                        ? (constraints.maxWidth - 24) / 3
                        : 300.0;
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        height: constraints.maxHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < TaskStatus.values.length; i++)
                              Padding(
                                padding: EdgeInsets.only(
                                  right: i == 2 ? 0 : 12,
                                ),
                                child: SizedBox(
                                  width: columnWidth,
                                  child: _Column(
                                    status: TaskStatus.values[i],
                                    tasks: filtered
                                        .where(
                                          (t) =>
                                              t.status == TaskStatus.values[i],
                                        )
                                        .toList(),
                                    onDrop: _move,
                                    onEdit: _editTask,
                                    onDelete: _delete,
                                    onToggleDone: _toggleDone,
                                  ),
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
                title: 'Could not load tasks',
                message: error.toString(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _move(Task task, TaskStatus status) async {
    if (task.status == status) return;
    await ref
        .read(tasksRepositoryProvider)
        .move(task, status, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _toggleDone(Task task) async {
    final next = task.status == TaskStatus.done
        ? TaskStatus.todo
        : TaskStatus.done;
    await _move(task, next);
  }

  Future<void> _editTask([Task? task]) => showTaskEditor(context, ref, task: task);

  Future<void> _delete(Task task) async {
    final ok = await confirmDialog(
      context,
      title: 'Move to trash?',
      message: '"${task.title}" can be restored from Trash for 30 days.',
      confirmLabel: 'Move to trash',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(tasksRepositoryProvider).softDelete(task.id);
    ref.invalidate(_tasksProvider);
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.status,
    required this.tasks,
    required this.onDrop,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleDone,
  });

  final TaskStatus status;
  final List<Task> tasks;
  final void Function(Task task, TaskStatus status) onDrop;
  final void Function(Task task) onEdit;
  final void Function(Task task) onDelete;
  final void Function(Task task) onToggleDone;

  @override
  Widget build(BuildContext context) {
    final accent = switch (status) {
      TaskStatus.todo => BrandColors.info,
      TaskStatus.doing => BrandColors.warning,
      TaskStatus.done => BrandColors.success,
    };
    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) => details.data.status != status,
      onAcceptWithDetails: (details) => onDrop(details.data, status),
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlighted
                  ? accent.withValues(alpha: 0.7)
                  : context.colors.outlineVariant.withValues(alpha: 0.4),
              width: highlighted ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    status.label,
                    style: context.theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${tasks.length}',
                      style: TextStyle(fontSize: 11, color: accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Text(
                          'Drop tasks here',
                          style: context.theme.textTheme.bodySmall?.copyWith(
                            color: context.colors.onSurface.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: tasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          return Draggable<Task>(
                            data: task,
                            feedback: Material(
                              color: Colors.transparent,
                              child: SizedBox(
                                width: 280,
                                child: _TaskCard(
                                  task: task,
                                  onEdit: () {},
                                  onDelete: () {},
                                  onToggleDone: () {},
                                  dragging: true,
                                ),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.35,
                              child: _TaskCard(
                                task: task,
                                onEdit: () => onEdit(task),
                                onDelete: () => onDelete(task),
                                onToggleDone: () => onToggleDone(task),
                              ),
                            ),
                            child: _TaskCard(
                              task: task,
                              onEdit: () => onEdit(task),
                              onDelete: () => onDelete(task),
                              onToggleDone: () => onToggleDone(task),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleDone,
    this.dragging = false,
  });

  final Task task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleDone;
  final bool dragging;

  Color get _priorityColor => switch (task.priority) {
    TaskPriority.high => BrandColors.danger,
    TaskPriority.medium => BrandColors.warning,
    TaskPriority.low => BrandColors.success,
  };

  @override
  Widget build(BuildContext context) {
    final subtasks = decodeListOfMaps(task.subtasksJson);
    final done = subtasks.where((s) => s['done'] == true).length;
    final overdue =
        task.dueDate != null &&
        task.dueDate!.isBefore(DateTime.now()) &&
        task.status != TaskStatus.done;

    return Card(
      margin: EdgeInsets.zero,
      elevation: dragging ? 8 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Task actions',
                    onSelected: (value) {
                      if (value == 'delete') onDelete();
                      if (value == 'done') onToggleDone();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'done',
                        child: Text(
                          task.status == TaskStatus.done
                              ? 'Reopen task'
                              : 'Mark done',
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
              if (task.description.trim().isNotEmpty) ...[
                Text(
                  truncate(task.description, 90),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              if (subtasks.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: subtasks.isEmpty ? 0 : done / subtasks.length,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$done/${subtasks.length}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: _priorityColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      task.priority.label,
                      style: TextStyle(fontSize: 9, color: _priorityColor),
                    ),
                  ),
                  if (task.dueDate != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.event_outlined,
                      size: 12,
                      color: overdue
                          ? BrandColors.danger
                          : context.colors.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      formatDate(task.dueDate),
                      style: TextStyle(
                        fontSize: 10,
                        color: overdue
                            ? BrandColors.danger
                            : context.colors.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (decodeStringList(task.tagsCsv).isNotEmpty ||
                      parseTags(task.tagsCsv).isNotEmpty)
                    Flexible(
                      child: Text(
                        parseTags(task.tagsCsv).join(' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          color: BrandColors.brass,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskFormDialog extends ConsumerStatefulWidget {
  const _TaskFormDialog({this.task});

  final Task? task;

  @override
  ConsumerState<_TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends ConsumerState<_TaskFormDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _tags;
  late TaskPriority _priority;
  late TaskStatus _status;
  DateTime? _dueDate;
  late List<Map<String, dynamic>> _subtasks;
  final List<TextEditingController> _subtaskControllers = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _title = TextEditingController(text: task?.title ?? '');
    _description = TextEditingController(text: task?.description ?? '');
    _tags = TextEditingController(text: task?.tagsCsv ?? '');
    _priority = task?.priority ?? TaskPriority.medium;
    _status = task?.status ?? TaskStatus.todo;
    _dueDate = task?.dueDate;
    _subtasks = task == null ? [] : decodeListOfMaps(task.subtasksJson);
    for (final subtask in _subtasks) {
      _subtaskControllers.add(
        TextEditingController(text: subtask['text'] as String? ?? ''),
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _tags.dispose();
    for (final controller in _subtaskControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addSubtask() {
    setState(() {
      _subtasks.add({'text': '', 'done': false});
      _subtaskControllers.add(TextEditingController());
    });
  }

  void _removeSubtask(int index) {
    setState(() {
      _subtasks.removeAt(index);
      _subtaskControllers.removeAt(index).dispose();
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showAppSnack(context, 'Give the task a title.', error: true);
      return;
    }
    setState(() => _saving = true);
    final subtasks = <Map<String, dynamic>>[];
    for (var i = 0; i < _subtasks.length; i++) {
      final text = _subtaskControllers[i].text.trim();
      if (text.isEmpty) continue;
      subtasks.add({'text': text, 'done': _subtasks[i]['done'] == true});
    }
    try {
      final repo = ref.read(tasksRepositoryProvider);
      final task = widget.task;
      if (task == null) {
        final created = await repo.create(
          title: _title.text,
          description: _description.text,
          status: _status,
          priority: _priority,
          dueDate: _dueDate,
          subtasks: subtasks,
          tagsCsv: _tags.text.trim(),
        );
        await repo.move(created, _status, created.sortOrder);
      } else {
        await repo.save(
          task,
          title: _title.text,
          description: _description.text,
          priority: _priority,
          dueDate: _dueDate,
          reminderAt: task.reminderAt,
          subtasks: subtasks,
          tagsCsv: _tags.text.trim(),
          linkedNoteId: task.linkedNoteId,
        );
        if (task.status != _status) {
          await repo.move(
            (await repo.byId(task.id))!,
            _status,
            DateTime.now().millisecondsSinceEpoch,
          );
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'Could not save task: $error', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.task == null ? 'New task' : 'Edit task'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                autofocus: widget.task == null,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                maxLines: 3,
                minLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<TaskPriority>(
                      initialValue: _priority,
                      decoration: const InputDecoration(
                        labelText: 'Priority',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final priority in TaskPriority.values)
                          DropdownMenuItem(
                            value: priority,
                            child: Text(priority.label),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _priority = value ?? _priority),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<TaskStatus>(
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final status in TaskStatus.values)
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
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event_outlined, size: 16),
                      label: Text(
                        _dueDate == null
                            ? 'Set due date'
                            : formatDate(_dueDate),
                      ),
                    ),
                  ),
                  if (_dueDate != null)
                    IconButton(
                      tooltip: 'Clear due date',
                      onPressed: () => setState(() => _dueDate = null),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tags,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma separated)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    'Subtasks',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addSubtask,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                  ),
                ],
              ),
              for (var i = 0; i < _subtasks.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _subtasks[i]['done'] == true,
                        onChanged: (value) => setState(
                          () => _subtasks[i]['done'] = value ?? false,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _subtaskControllers[i],
                          decoration: const InputDecoration(
                            hintText: 'Subtask',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _removeSubtask(i),
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ],
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
