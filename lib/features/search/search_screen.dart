import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../services/search/search_service.dart';
import '../../widgets/common.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<SearchHit> _hits = const [];
  bool _loading = false;
  String _query = '';
  String? _filter;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _run);
  }

  Future<void> _run() async {
    if (_query.trim().isEmpty) {
      setState(() {
        _hits = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    final hits = await ref.read(searchServiceProvider).search(_query);
    if (!mounted) return;
    setState(() {
      _hits = hits;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter == null
        ? _hits
        : _hits.where((hit) => hit.entityType == _filter).toList();
    final types = <String>{for (final hit in _hits) hit.entityType};

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Search',
            subtitle: 'Full-text search across your notes and tasks.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            autofocus: true,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: 'Search everything… (Ctrl+K)',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: () {
                        _search.clear();
                        _onChanged('');
                      },
                      icon: const Icon(Icons.close),
                    ),
              isDense: true,
            ),
          ),
          if (_hits.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: Text(
                    'All (${_hits.length})',
                    style: const TextStyle(fontSize: 11),
                  ),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                for (final type in types)
                  ChoiceChip(
                    label: Text(
                      '${_label(type)} (${_hits.where((h) => h.entityType == type).length})',
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: _filter == type,
                    onSelected: (_) => setState(() => _filter = type),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _query.trim().isEmpty
                ? const EmptyState(
                    icon: Icons.search,
                    title: 'Search your notes and tasks',
                    message:
                        'Try a title, a word from the body, a tag or a phrase.',
                  )
                : filtered.isEmpty
                ? EmptyState(
                    icon: Icons.search_off,
                    title: 'No results',
                    message:
                        'Nothing matched "$_query". Try fewer words or a different spelling.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final hit = filtered[index];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: Icon(
                            _icon(hit.entityType),
                            color: BrandColors.brass,
                          ),
                          title: Text(
                            hit.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text(
                                _label(hit.entityType),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: BrandColors.brass,
                                ),
                              ),
                              Text(
                                hit.snippet.replaceAll(RegExp(r'\s+'), ' '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: context.theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                          onTap: () => _open(hit),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _label(String type) => switch (type) {
    'notes' => 'Note',
    'tasks' => 'Task',
    _ => type,
  };

  IconData _icon(String type) => switch (type) {
    'notes' => Icons.sticky_note_2_outlined,
    'tasks' => Icons.checklist_rounded,
    _ => Icons.search,
  };

  void _open(SearchHit hit) {
    switch (hit.entityType) {
      case 'notes':
        context.go('/notes/${hit.entityId}');
      case 'tasks':
        context.go('/tasks');
    }
  }
}
