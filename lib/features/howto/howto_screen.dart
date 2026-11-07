import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../widgets/common.dart';

final _howToProvider = StreamProvider.autoDispose<List<HowTo>>(
  (ref) => ref.watch(howToRepositoryProvider).watchActive(),
);

class HowToScreen extends ConsumerStatefulWidget {
  const HowToScreen({super.key});

  @override
  ConsumerState<HowToScreen> createState() => _HowToScreenState();
}

class _HowToScreenState extends ConsumerState<HowToScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _category = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(_howToProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'How-To Library',
            subtitle: 'Runbooks and procedures you can trust when it matters.',
            action: FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('New how-to'),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Search procedures, categories or tags…',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          rows.maybeWhen(
            data: (items) {
              final categories = <String>{'All'};
              for (final item in items) {
                if (item.category.trim().isNotEmpty) {
                  categories.add(item.category.trim());
                }
              }
              return SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final category in categories)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            category,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: _category == category,
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                      ),
                  ],
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: rows.when(
              data: (items) {
                final filtered = items.where((item) {
                  if (_category != 'All' && item.category.trim() != _category) {
                    return false;
                  }
                  if (_query.trim().isEmpty) return true;
                  final needle = _query.toLowerCase();
                  return item.title.toLowerCase().contains(needle) ||
                      item.stepsJson.toLowerCase().contains(needle) ||
                      item.tagsCsv.toLowerCase().contains(needle) ||
                      item.category.toLowerCase().contains(needle);
                }).toList();

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.menu_book_outlined,
                    title: items.isEmpty
                        ? 'No how-tos yet'
                        : 'Nothing matches those filters',
                    message: items.isEmpty
                        ? 'Document the next thing you fix, so the fix is never lost.'
                        : 'Try another search term or category.',
                    action: items.isEmpty
                        ? FilledButton.icon(
                            onPressed: _create,
                            icon: const Icon(Icons.add),
                            label: const Text('Write a how-to'),
                          )
                        : null,
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _HowToCard(howTo: filtered[index]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Could not load how-tos',
                message: error.toString(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final title = TextEditingController();
    final category = TextEditingController(text: 'Servers');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New how-to'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: category,
              decoration: const InputDecoration(labelText: 'Category'),
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final row = await ref
        .read(howToRepositoryProvider)
        .create(
          title: title.text.trim().isEmpty ? 'New how-to' : title.text.trim(),
          category: category.text.trim().isEmpty
              ? 'Servers'
              : category.text.trim(),
        );
    ref.invalidate(_howToProvider);
    if (mounted) context.go('/howto/${row.id}');
  }
}

class _HowToCard extends StatelessWidget {
  const _HowToCard({required this.howTo});

  final HowTo howTo;

  Color get _difficultyColor => switch (howTo.difficulty) {
    HowToDifficulty.easy => BrandColors.success,
    HowToDifficulty.medium => BrandColors.warning,
    HowToDifficulty.hard => BrandColors.danger,
  };

  @override
  Widget build(BuildContext context) {
    final tags = parseTags(howTo.tagsCsv);
    final stale = isStale(howTo.lastTested);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.go('/howto/${howTo.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _difficultyColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  color: _difficultyColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            howTo.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: BrandColors.brass.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            howTo.category,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          howTo.difficulty.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: _difficultyColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          howTo.lastTested == null
                              ? 'Never tested'
                              : 'Tested ${formatDate(howTo.lastTested)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: stale
                                ? BrandColors.danger
                                : context.colors.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                          ),
                        ),
                        if (stale && howTo.lastTested != null) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 13,
                            color: BrandColors.danger,
                          ),
                        ],
                      ],
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 5,
                        children: [
                          for (final tag in tags)
                            Text(
                              tag,
                              style: TextStyle(
                                fontSize: 10,
                                color: BrandColors.brass.withValues(alpha: 0.9),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
