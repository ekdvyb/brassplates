import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../widgets/common.dart';
import 'diagram_export_service.dart';
import 'diagram_model.dart';
import 'diagram_painter.dart';
import 'diagram_templates.dart';

final _diagramsProvider = StreamProvider.autoDispose<List<Diagram>>(
  (ref) => ref.watch(diagramsRepositoryProvider).watchActive(),
);

class DiagramsScreen extends ConsumerStatefulWidget {
  const DiagramsScreen({super.key});

  @override
  ConsumerState<DiagramsScreen> createState() => _DiagramsScreenState();
}

class _DiagramsScreenState extends ConsumerState<DiagramsScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _grid = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diagrams = ref.watch(_diagramsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Diagrams Studio',
            subtitle: 'Network topology, data flows and troubleshooting maps with real metadata.',
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
                  onPressed: _chooseTemplate,
                  icon: const Icon(Icons.add),
                  label: const Text('New diagram'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Search diagrams, labels, IPs and hosts…',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: diagrams.when(
              data: (rows) {
                final filtered = rows.where((diagram) {
                  if (_query.trim().isEmpty) return true;
                  final needle = _query.toLowerCase();
                  return diagram.title.toLowerCase().contains(needle) ||
                      diagram.searchText.toLowerCase().contains(needle);
                }).toList();

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.account_tree_outlined,
                    title: rows.isEmpty ? 'No diagrams yet' : 'No matches',
                    message: rows.isEmpty
                        ? 'Start from a template: network topology, SQL Vault, FDMS, trading stack and more.'
                        : 'Try another search term.',
                    action: rows.isEmpty
                        ? FilledButton.icon(
                            onPressed: _chooseTemplate,
                            icon: const Icon(Icons.add),
                            label: const Text('Create a diagram'),
                          )
                        : null,
                  );
                }

                if (!_grid) {
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _DiagramRow(
                      diagram: filtered[index],
                      onDelete: () => _delete(filtered[index]),
                      onDuplicate: () => _duplicate(filtered[index]),
                      onExport: (format) => _export(filtered[index], format),
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 360,
                    mainAxisExtent: 240,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => _DiagramCard(
                    diagram: filtered[index],
                    onDelete: () => _delete(filtered[index]),
                    onDuplicate: () => _duplicate(filtered[index]),
                    onExport: (format) => _export(filtered[index], format),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Could not load diagrams',
                message: error.toString(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseTemplate() async {
    final template = await showDialog<DiagramTemplate>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a diagram'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              mainAxisExtent: 120,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: diagramTemplates.length,
            itemBuilder: (context, index) {
              final template = diagramTemplates[index];
              return Card(
                margin: EdgeInsets.zero,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(context, template),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _templateIcon(template.id),
                          color: BrandColors.brass,
                          size: 22,
                        ),
                        const Spacer(),
                        Text(
                          template.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          template.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.theme.textTheme.bodySmall?.copyWith(
                            color: context.colors.onSurface.withValues(
                              alpha: 0.6,
                            ),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (template == null) return;
    final document = template.build();
    final row = await ref
        .read(diagramsRepositoryProvider)
        .create(
          title: document.title,
          documentJson: document.toJson(),
          searchText: document.searchableText,
        );
    ref.invalidate(_diagramsProvider);
    if (mounted) context.go('/diagrams/${row.id}');
  }

  IconData _templateIcon(String id) => switch (id) {
    'network' => Icons.lan_outlined,
    'sql-vault' => Icons.storage_outlined,
    'fdms' => Icons.dns_outlined,
    'trading' => Icons.candlestick_chart_outlined,
    'erd' => Icons.table_chart_outlined,
    'troubleshooting' => Icons.troubleshoot,
    _ => Icons.crop_square,
  };

  Future<void> _delete(Diagram diagram) async {
    final ok = await confirmDialog(
      context,
      title: 'Move to trash?',
      message: '"${diagram.title}" can be restored from Trash for 30 days.',
      confirmLabel: 'Move to trash',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(diagramsRepositoryProvider).softDelete(diagram.id);
    ref.invalidate(_diagramsProvider);
  }

  Future<void> _duplicate(Diagram diagram) async {
    final title = '${diagram.title} copy';
    final row = await ref
        .read(diagramsRepositoryProvider)
        .create(
          title: title,
          documentJson: diagram.documentJson,
          searchText: diagram.searchText,
        );
    ref.invalidate(_diagramsProvider);
    if (mounted) context.go('/diagrams/${row.id}');
  }

  Future<void> _export(Diagram diagram, String format) async {
    final document = DiagramDocument.fromJson(diagram.documentJson);
    try {
      List<int> bytes;
      String extension;
      switch (format) {
        case 'svg':
          bytes = utf8.encode(DiagramExportService.svg(document));
          extension = 'svg';
        case 'pdf':
          bytes = await DiagramExportService.pdf(document);
          extension = 'pdf';
        default:
          bytes = await DiagramExportService.png(document);
          extension = 'png';
      }
      await FilePicker.saveFile(
        dialogTitle: 'Export diagram',
        fileName: '${_safeName(diagram.title)}.$extension',
        bytes: Uint8List.fromList(bytes),
      );
      if (mounted) showAppSnack(context, 'Diagram exported.');
    } catch (error) {
      if (mounted) {
        showAppSnack(context, 'Export failed: $error', error: true);
      }
    }
  }

  String _safeName(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '').trim().isEmpty
      ? 'diagram'
      : value.replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '').trim();
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.diagram});

  final Diagram diagram;
  final bool dark = false;

  @override
  Widget build(BuildContext context) {
    if (diagram.thumbnailBase64 != null &&
        diagram.thumbnailBase64!.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(diagram.thumbnailBase64!),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      } catch (_) {}
    }
    final document = DiagramDocument.fromJson(diagram.documentJson);
    return LayoutBuilder(
      builder: (context, constraints) => ClipRect(
        child: CustomPaint(
          painter: DiagramPainter(
            document: document,
            viewport: _fitViewport(
              document,
              Size(
                constraints.maxWidth.isFinite ? constraints.maxWidth : 320,
                constraints.maxHeight.isFinite ? constraints.maxHeight : 140,
              ),
            ),
            showGrid: false,
            dark: dark,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  DiagramViewport _fitViewport(DiagramDocument document, Size size) {
    final bounds = DiagramExportService.documentBounds(document);
    final width = size.width.clamp(1, 340).toDouble();
    final height = size.height.clamp(1, 240).toDouble();
    final scale =
        (width / bounds.width).clamp(0.05, 1.0) <
            (height / bounds.height).clamp(0.05, 1.0)
        ? (width / bounds.width).clamp(0.05, 1.0)
        : (height / bounds.height).clamp(0.05, 1.0);
    return DiagramViewport(
      dx: -bounds.left * scale + (width - bounds.width * scale) / 2,
      dy: -bounds.top * scale + (height - bounds.height * scale) / 2,
      scale: scale,
    );
  }
}

class _DiagramCard extends StatelessWidget {
  const _DiagramCard({
    required this.diagram,
    required this.onDelete,
    required this.onDuplicate,
    required this.onExport,
  });

  final Diagram diagram;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final void Function(String format) onExport;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/diagrams/${diagram.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: context.colors.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Thumbnail(diagram: diagram),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: _Menu(
                        onDelete: onDelete,
                        onDuplicate: onDuplicate,
                        onExport: onExport,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    diagram.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Updated ${timeAgo(diagram.updatedAt)}',
                    style: context.theme.textTheme.labelSmall?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.5),
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

class _DiagramRow extends StatelessWidget {
  const _DiagramRow({
    required this.diagram,
    required this.onDelete,
    required this.onDuplicate,
    required this.onExport,
  });

  final Diagram diagram;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final void Function(String format) onExport;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: SizedBox(
          width: 64,
          height: 44,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              color: context.colors.surfaceContainerHighest.withValues(
                alpha: 0.35,
              ),
              child: _Thumbnail(diagram: diagram),
            ),
          ),
        ),
        title: Text(
          diagram.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('Updated ${timeAgo(diagram.updatedAt)}'),
        onTap: () => context.go('/diagrams/${diagram.id}'),
        trailing: _Menu(
          onDelete: onDelete,
          onDuplicate: onDuplicate,
          onExport: onExport,
        ),
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({
    required this.onDelete,
    required this.onDuplicate,
    required this.onExport,
  });

  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final void Function(String format) onExport;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Diagram actions',
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (value) {
        switch (value) {
          case 'duplicate':
            onDuplicate();
          case 'delete':
            onDelete();
          case 'png':
          case 'svg':
          case 'pdf':
            onExport(value);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        PopupMenuItem(value: 'png', child: Text('Export PNG')),
        PopupMenuItem(value: 'svg', child: Text('Export SVG')),
        PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
        PopupMenuItem(value: 'delete', child: Text('Move to trash')),
      ],
    );
  }
}
