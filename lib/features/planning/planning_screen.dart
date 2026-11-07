import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../widgets/common.dart';

final _projectsProvider = StreamProvider.autoDispose<List<Project>>(
  (ref) => ref.watch(planningRepositoryProvider).watchProjects(),
);

final _milestonesProvider = StreamProvider.autoDispose
    .family<List<Milestone>, String>(
      (ref, projectId) =>
          ref.watch(planningRepositoryProvider).watchMilestones(projectId),
    );

class PlanningScreen extends ConsumerStatefulWidget {
  const PlanningScreen({super.key});

  @override
  ConsumerState<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends ConsumerState<PlanningScreen> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(_projectsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Planning',
            subtitle:
                'Roadmaps, milestones and progress that survives handovers.',
            action: FilledButton.icon(
              onPressed: () => _editProject(),
              icon: const Icon(Icons.add),
              label: const Text('New project'),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: projects.when(
              data: (rows) {
                if (rows.isEmpty) {
                  return EmptyState(
                    icon: Icons.flag_outlined,
                    title: 'No projects yet',
                    message: 'Plan a migration, rollout or maintenance window and track it to done.',
                    action: FilledButton.icon(
                      onPressed: () => _editProject(),
                      icon: const Icon(Icons.add),
                      label: const Text('Create a project'),
                    ),
                  );
                }
                final selected = rows.firstWhere(
                  (project) => project.id == _selectedId,
                  orElse: () => rows.first,
                );
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 900;
                    final list = _ProjectList(
                      projects: rows,
                      selectedId: selected.id,
                      onSelect: (project) =>
                          setState(() => _selectedId = project.id),
                      onEdit: _editProject,
                      onDelete: _deleteProject,
                    );
                    final detail = _ProjectDetail(
                      key: ValueKey(selected.id),
                      project: selected,
                      onEdit: () => _editProject(selected),
                      onDelete: () => _deleteProject(selected),
                      onProgressChanged: (value) =>
                          _setProgress(selected, value),
                      onStatusChanged: (status) => _setStatus(selected, status),
                      onAddMilestone: () => _addMilestone(selected),
                      onBack: wide
                          ? null
                          : () => setState(() => _selectedId = null),
                    );

                    if (!wide) {
                      if (_selectedId == null) return list;
                      return detail;
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 340, child: list),
                        const SizedBox(width: 16),
                        Expanded(child: detail),
                      ],
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Could not load projects',
                message: error.toString(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setProgress(Project project, int progress) async {
    await ref
        .read(planningRepositoryProvider)
        .saveProject(
          project,
          title: project.title,
          description: project.description,
          status: project.status,
          startDate: project.startDate,
          endDate: project.endDate,
          progress: progress,
        );
  }

  Future<void> _setStatus(Project project, ProjectStatus status) async {
    await ref
        .read(planningRepositoryProvider)
        .saveProject(
          project,
          title: project.title,
          description: project.description,
          status: status,
          startDate: project.startDate,
          endDate: project.endDate,
          progress: project.progress,
        );
  }

  Future<void> _addMilestone(Project project) async {
    final title = TextEditingController();
    DateTime? due;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New milestone'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Milestone'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: due ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 365),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) setState(() => due = picked);
                },
                icon: const Icon(Icons.event_outlined, size: 16),
                label: Text(due == null ? 'Set due date' : formatDate(due)),
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
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (title.text.trim().isEmpty) return;
    await ref
        .read(planningRepositoryProvider)
        .addMilestone(project.id, title: title.text.trim(), dueDate: due);
  }

  Future<void> _editProject([Project? project]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ProjectDialog(project: project),
    );
    if (saved == true) {
      ref.invalidate(_projectsProvider);
    }
  }

  Future<void> _deleteProject(Project project) async {
    final ok = await confirmDialog(
      context,
      title: 'Move project to trash?',
      message:
          '"${project.title}" and its milestones will be recoverable for 30 days.',
      confirmLabel: 'Move to trash',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(planningRepositoryProvider).softDeleteProject(project.id);
    if (_selectedId == project.id) setState(() => _selectedId = null);
  }
}

class _ProjectList extends StatelessWidget {
  const _ProjectList({
    required this.projects,
    required this.selectedId,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Project> projects;
  final String selectedId;
  final void Function(Project project) onSelect;
  final void Function(Project project) onEdit;
  final void Function(Project project) onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: projects.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final project = projects[index];
        final selected = project.id == selectedId;
        return Card(
          margin: EdgeInsets.zero,
          color: selected ? BrandColors.brass.withValues(alpha: 0.1) : null,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onSelect(project),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          project.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Project actions',
                        onSelected: (value) {
                          if (value == 'edit') onEdit(project);
                          if (value == 'delete') onDelete(project);
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit project'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Move to trash'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: project.progress / 100,
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        '${project.progress}%',
                        style: const TextStyle(fontSize: 10),
                      ),
                      const SizedBox(width: 8),
                      if (project.endDate != null)
                        Text(
                          'Due ${formatDate(project.endDate)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: context.colors.onSurface.withValues(
                              alpha: 0.5,
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
      },
    );
  }
}

class _ProjectDetail extends ConsumerWidget {
  const _ProjectDetail({
    super.key,
    required this.project,
    required this.onEdit,
    required this.onDelete,
    required this.onProgressChanged,
    required this.onStatusChanged,
    required this.onAddMilestone,
    this.onBack,
  });

  final Project project;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final void Function(int progress) onProgressChanged;
  final void Function(ProjectStatus status) onStatusChanged;
  final VoidCallback onAddMilestone;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final milestones = ref.watch(_milestonesProvider(project.id));

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (onBack != null)
                      IconButton(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back),
                      ),
                    Expanded(
                      child: Text(
                        project.title,
                        style: context.theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit project',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Move to trash',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                if (project.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    project.description,
                    style: context.theme.textTheme.bodyMedium?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownButton<ProjectStatus>(
                      value: project.status,
                      onChanged: (value) {
                        if (value != null) onStatusChanged(value);
                      },
                      items: [
                        for (final status in ProjectStatus.values)
                          DropdownMenuItem(
                            value: status,
                            child: Text(_label(status)),
                          ),
                      ],
                    ),
                    if (project.startDate != null)
                      Chip(
                        label: Text(
                          'Start ${formatDate(project.startDate)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (project.endDate != null)
                      Chip(
                        label: Text(
                          'Due ${formatDate(project.endDate)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      'Progress',
                      style: context.theme.textTheme.labelMedium,
                    ),
                    Expanded(
                      child: Slider(
                        value: project.progress.toDouble(),
                        max: 100,
                        divisions: 20,
                        label: '${project.progress}%',
                        onChanged: (value) => onProgressChanged(value.round()),
                      ),
                    ),
                    Text('${project.progress}%'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.flag_outlined,
                      size: 18,
                      color: BrandColors.brass,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Milestones',
                      style: context.theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: onAddMilestone,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                milestones.when(
                  data: (rows) => rows.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'No milestones yet. Break the project into checkpoints.',
                            style: context.theme.textTheme.bodySmall?.copyWith(
                              color: context.colors.onSurface.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            for (final milestone in rows)
                              CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: milestone.done,
                                onChanged: (_) => ref
                                    .read(planningRepositoryProvider)
                                    .toggleMilestone(milestone),
                                title: Text(
                                  milestone.title,
                                  style: TextStyle(
                                    decoration: milestone.done
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                subtitle: milestone.dueDate == null
                                    ? null
                                    : Text(
                                        'Due ${formatDate(milestone.dueDate)}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                secondary: IconButton(
                                  tooltip: 'Delete milestone',
                                  onPressed: () => ref
                                      .read(planningRepositoryProvider)
                                      .deleteMilestone(milestone.id),
                                  icon: const Icon(Icons.close, size: 16),
                                ),
                              ),
                          ],
                        ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Text(error.toString()),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _label(ProjectStatus status) => switch (status) {
    ProjectStatus.planned => 'Planned',
    ProjectStatus.active => 'Active',
    ProjectStatus.onHold => 'On hold',
    ProjectStatus.done => 'Done',
  };
}

class _ProjectDialog extends ConsumerStatefulWidget {
  const _ProjectDialog({this.project});

  final Project? project;

  @override
  ConsumerState<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends ConsumerState<_ProjectDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late ProjectStatus _status;
  DateTime? _start;
  DateTime? _end;
  late double _progress;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.project?.title ?? '');
    _description = TextEditingController(
      text: widget.project?.description ?? '',
    );
    _status = widget.project?.status ?? ProjectStatus.active;
    _start = widget.project?.startDate;
    _end = widget.project?.endDate;
    _progress = (widget.project?.progress ?? 0).toDouble();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (start ? _start : _end) ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() {
        if (start) {
          _start = picked;
        } else {
          _end = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showAppSnack(context, 'Give the project a title.', error: true);
      return;
    }
    final repo = ref.read(planningRepositoryProvider);
    if (widget.project == null) {
      await repo.createProject(
        title: _title.text.trim(),
        description: _description.text,
        status: _status,
        startDate: _start,
        endDate: _end,
      );
    } else {
      await repo.saveProject(
        widget.project!,
        title: _title.text.trim(),
        description: _description.text,
        status: _status,
        startDate: _start,
        endDate: _end,
        progress: _progress.round(),
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.project == null ? 'New project' : 'Edit project'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                autofocus: true,
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
              DropdownButtonFormField<ProjectStatus>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: ProjectStatus.planned,
                    child: Text('Planned'),
                  ),
                  DropdownMenuItem(
                    value: ProjectStatus.active,
                    child: Text('Active'),
                  ),
                  DropdownMenuItem(
                    value: ProjectStatus.onHold,
                    child: Text('On hold'),
                  ),
                  DropdownMenuItem(
                    value: ProjectStatus.done,
                    child: Text('Done'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _status = value ?? _status),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pick(start: true),
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: Text(
                        _start == null ? 'Start date' : formatDate(_start),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pick(start: false),
                      icon: const Icon(Icons.flag_outlined, size: 16),
                      label: Text(_end == null ? 'End date' : formatDate(_end)),
                    ),
                  ),
                ],
              ),
              if (widget.project != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Progress'),
                    Expanded(
                      child: Slider(
                        value: _progress,
                        max: 100,
                        divisions: 20,
                        label: '${_progress.round()}%',
                        onChanged: (value) => setState(() => _progress = value),
                      ),
                    ),
                    Text('${_progress.round()}%'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
