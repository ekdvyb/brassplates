import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../widgets/common.dart';

class _StepEdit {
  _StepEdit({String text = '', this.code = false, String language = ''})
    : text = TextEditingController(text: text),
      language = TextEditingController(text: language);

  final TextEditingController text;
  final TextEditingController language;
  bool code;

  void dispose() {
    text.dispose();
    language.dispose();
  }
}

class HowToDetailScreen extends ConsumerStatefulWidget {
  const HowToDetailScreen({super.key, required this.howToId});

  final String howToId;

  @override
  ConsumerState<HowToDetailScreen> createState() => _HowToDetailScreenState();
}

class _HowToDetailScreenState extends ConsumerState<HowToDetailScreen> {
  HowTo? _howTo;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  String? _error;

  final _title = TextEditingController();
  final _category = TextEditingController();
  final _tags = TextEditingController();
  HowToDifficulty _difficulty = HowToDifficulty.easy;
  final List<_StepEdit> _steps = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _category.dispose();
    _tags.dispose();
    for (final step in _steps) {
      step.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final row = await ref.read(howToRepositoryProvider).byId(widget.howToId);
    if (!mounted) return;
    if (row == null) {
      setState(() {
        _loading = false;
        _error = 'This how-to no longer exists.';
      });
      return;
    }
    _howTo = row;
    _title.text = row.title;
    _category.text = row.category;
    _tags.text = row.tagsCsv;
    _difficulty = row.difficulty;
    for (final step in _steps) {
      step.dispose();
    }
    _steps
      ..clear()
      ..addAll(
        decodeListOfMaps(row.stepsJson).map(
          (step) => _StepEdit(
            text: step['text'] as String? ?? '',
            code: step['type'] == 'code',
            language: step['language'] as String? ?? '',
          ),
        ),
      );
    if (_steps.isEmpty) _steps.add(_StepEdit());
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final howTo = _howTo;
    if (howTo == null) return;
    setState(() => _saving = true);
    final steps = <Map<String, dynamic>>[];
    for (final step in _steps) {
      if (step.text.text.trim().isEmpty) continue;
      steps.add({
        'type': step.code ? 'code' : 'text',
        'text': step.text.text,
        if (step.code && step.language.text.trim().isNotEmpty)
          'language': step.language.text.trim(),
      });
    }
    try {
      final updated = await ref
          .read(howToRepositoryProvider)
          .save(
            howTo,
            title: _title.text,
            category: _category.text.trim().isEmpty
                ? 'General'
                : _category.text.trim(),
            difficulty: _difficulty,
            steps: steps,
            tagsCsv: _tags.text.trim(),
            lastTested: howTo.lastTested,
          );
      if (!mounted) return;
      setState(() {
        _howTo = updated;
        _editing = false;
        _saving = false;
      });
      showAppSnack(context, 'How-to saved.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'Could not save: $error', error: true);
    }
  }

  Future<void> _markTested() async {
    final howTo = _howTo;
    if (howTo == null) return;
    await ref.read(howToRepositoryProvider).markTested(howTo);
    await _load();
    if (mounted) showAppSnack(context, 'Marked as tested today.');
  }

  Future<void> _delete() async {
    final howTo = _howTo;
    if (howTo == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Move to trash?',
      message: '"${howTo.title}" can be restored from Trash for 30 days.',
      confirmLabel: 'Move to trash',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(howToRepositoryProvider).softDelete(howTo.id);
    if (mounted) context.go('/howto');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _howTo == null) {
      return EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'How-to unavailable',
        message: _error ?? 'The how-to could not be opened.',
        action: TextButton(
          onPressed: () => context.go('/howto'),
          child: const Text('Back to library'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back to library',
                onPressed: () => context.go('/howto'),
                icon: const Icon(Icons.arrow_back),
              ),
              const Spacer(),
              if (!_editing)
                OutlinedButton.icon(
                  onPressed: _markTested,
                  icon: const Icon(Icons.verified_outlined, size: 16),
                  label: const Text('Mark tested'),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _editing
                    ? (_saving ? null : _save)
                    : () => setState(() => _editing = true),
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _editing ? Icons.save_outlined : Icons.edit_outlined,
                        size: 16,
                      ),
                label: Text(_editing ? 'Save' : 'Edit'),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (value) {
                  if (value == 'delete') _delete();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'delete', child: Text('Move to trash')),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_editing) ...[
                      TextField(
                        controller: _title,
                        style: context.theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _category,
                              decoration: const InputDecoration(
                                labelText: 'Category',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          DropdownButton<HowToDifficulty>(
                            value: _difficulty,
                            onChanged: (value) => setState(
                              () => _difficulty = value ?? _difficulty,
                            ),
                            items: [
                              for (final difficulty in HowToDifficulty.values)
                                DropdownMenuItem(
                                  value: difficulty,
                                  child: Text(difficulty.label),
                                ),
                            ],
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
                      const SizedBox(height: 20),
                      Text(
                        'Steps',
                        style: context.theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _steps.length; i++)
                        _StepEditor(
                          key: ValueKey(_steps[i]),
                          index: i,
                          step: _steps[i],
                          onRemove: _steps.length == 1
                              ? null
                              : () => setState(() {
                                  _steps.removeAt(i).dispose();
                                }),
                          onMoveUp: i == 0
                              ? null
                              : () => setState(() {
                                  final step = _steps.removeAt(i);
                                  _steps.insert(i - 1, step);
                                }),
                          onMoveDown: i == _steps.length - 1
                              ? null
                              : () => setState(() {
                                  final step = _steps.removeAt(i);
                                  _steps.insert(i + 1, step);
                                }),
                          onToggleCode: () =>
                              setState(() => _steps[i].code = !_steps[i].code),
                        ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => _steps.add(_StepEdit())),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add step'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => setState(
                              () => _steps.add(
                                _StepEdit(code: true, language: 'bash'),
                              ),
                            ),
                            icon: const Icon(Icons.code, size: 16),
                            label: const Text('Add code block'),
                          ),
                        ],
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _howTo!.title,
                              style: context.theme.textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Chip(
                            label: Text(
                              _howTo!.category,
                              style: const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          Chip(
                            label: Text(
                              _howTo!.difficulty.label,
                              style: const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          Text(
                            _howTo!.lastTested == null
                                ? 'Never tested'
                                : 'Last tested ${formatDate(_howTo!.lastTested)}',
                            style: context.theme.textTheme.bodySmall?.copyWith(
                              color: isStale(_howTo!.lastTested)
                                  ? BrandColors.danger
                                  : context.colors.onSurface.withValues(
                                      alpha: 0.55,
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      for (var i = 0; i < _steps.length; i++)
                        if (_steps[i].text.text.trim().isNotEmpty)
                          _StepView(index: i, step: _steps[i]),
                      if (_steps.every((s) => s.text.text.trim().isEmpty))
                        const EmptyState(
                          icon: Icons.notes_outlined,
                          title: 'No steps yet',
                          message: 'Tap Edit to document the procedure step by step.',
                        ),
                      const SizedBox(height: 20),
                      TagChips(tags: parseTags(_howTo!.tagsCsv)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepEditor extends StatelessWidget {
  const _StepEditor({
    super.key,
    required this.index,
    required this.step,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggleCode,
  });

  final int index;
  final _StepEdit step;
  final VoidCallback? onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onToggleCode;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: BrandColors.brass.withValues(alpha: 0.16),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  step.code ? 'Code block' : 'Step',
                  style: context.theme.textTheme.labelMedium,
                ),
                const Spacer(),
                IconButton(
                  tooltip: step.code ? 'Make text step' : 'Make code block',
                  onPressed: onToggleCode,
                  icon: Icon(step.code ? Icons.notes : Icons.code, size: 18),
                ),
                IconButton(
                  tooltip: 'Move up',
                  onPressed: onMoveUp,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                IconButton(
                  tooltip: 'Move down',
                  onPressed: onMoveDown,
                  icon: const Icon(Icons.arrow_downward, size: 18),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            TextField(
              controller: step.text,
              maxLines: null,
              minLines: step.code ? 3 : 2,
              style: step.code
                  ? const TextStyle(fontFamily: 'monospace', fontSize: 13)
                  : null,
              decoration: InputDecoration(
                hintText: step.code ? 'Command or snippet' : 'What to do',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            if (step.code) ...[
              const SizedBox(height: 8),
              TextField(
                controller: step.language,
                decoration: const InputDecoration(
                  labelText: 'Language',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepView extends StatelessWidget {
  const _StepView({required this.index, required this.step});

  final int index;
  final _StepEdit step;

  @override
  Widget build(BuildContext context) {
    if (step.code) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1B17),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: BrandColors.brass.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
                child: Row(
                  children: [
                    Text(
                      step.language.text.isEmpty ? 'code' : step.language.text,
                      style: const TextStyle(
                        fontSize: 10,
                        color: BrandColors.brassLight,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Copy',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.copy,
                        size: 15,
                        color: Colors.white70,
                      ),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: step.text.text),
                        );
                        if (context.mounted) {
                          showAppSnack(context, 'Copied.');
                        }
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SelectableText(
                  step.text.text,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Color(0xFFE8E0D2),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: BrandColors.brass.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              step.text.text,
              style: context.theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
