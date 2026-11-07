import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../widgets/common.dart';
import 'diagram_export_service.dart';
import 'diagram_model.dart';
import 'diagram_painter.dart';

enum _Tool {
  select,
  pan,
  connector,
  rectangle,
  ellipse,
  diamond,
  text,
  sticky,
  server,
  database,
  sqlServer,
  firewall,
  cloud,
  router,
  networkSwitch,
  loadBalancer,
  storage,
  nextcloud,
}

DiagramShapeType? _shapeTypeForTool(_Tool tool) => switch (tool) {
  _Tool.rectangle => DiagramShapeType.rectangle,
  _Tool.ellipse => DiagramShapeType.ellipse,
  _Tool.diamond => DiagramShapeType.diamond,
  _Tool.text => DiagramShapeType.text,
  _Tool.sticky => DiagramShapeType.sticky,
  _Tool.server => DiagramShapeType.server,
  _Tool.database => DiagramShapeType.database,
  _Tool.sqlServer => DiagramShapeType.sqlServer,
  _Tool.firewall => DiagramShapeType.firewall,
  _Tool.cloud => DiagramShapeType.cloud,
  _Tool.router => DiagramShapeType.router,
  _Tool.networkSwitch => DiagramShapeType.networkSwitch,
  _Tool.loadBalancer => DiagramShapeType.loadBalancer,
  _Tool.storage => DiagramShapeType.storage,
  _Tool.nextcloud => DiagramShapeType.nextcloud,
  _ => null,
};

class DiagramEditorScreen extends ConsumerStatefulWidget {
  const DiagramEditorScreen({super.key, required this.diagramId});

  final String diagramId;

  @override
  ConsumerState<DiagramEditorScreen> createState() =>
      _DiagramEditorScreenState();
}

class _DiagramEditorScreenState extends ConsumerState<DiagramEditorScreen> {
  Diagram? _row;
  DiagramDocument _doc = DiagramDocument();
  DiagramViewport _viewport = const DiagramViewport();
  final _title = TextEditingController();
  final _canvasKey = GlobalKey();
  Timer? _debounce;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;
  DateTime? _savedAt;

  _Tool _tool = _Tool.select;
  String? _selectedShapeId;
  String? _selectedConnectorId;
  String? _connectFromId;
  bool _showGrid = true;
  bool _canvasDark = false;
  final bool _inspectorOpen = true;

  DiagramShape? _dragShape;
  Offset _dragStart = Offset.zero;
  Offset _dragOrigin = Offset.zero;
  bool _dragMoved = false;

  final List<String> _undoStack = [];
  final List<String> _redoStack = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DiagramEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diagramId != widget.diagramId) {
      _teardown();
      _load();
    }
  }

  @override
  void dispose() {
    _teardown();
    _title.dispose();
    super.dispose();
  }

  void _teardown() {
    _debounce?.cancel();
    _flush();
    _row = null;
    _doc = DiagramDocument();
    _selectedShapeId = null;
    _selectedConnectorId = null;
    _dirty = false;
    _undoStack.clear();
    _redoStack.clear();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final row = await ref
        .read(diagramsRepositoryProvider)
        .byId(widget.diagramId);
    if (!mounted) return;
    if (row == null) {
      setState(() {
        _loading = false;
        _error = 'This diagram no longer exists.';
      });
      return;
    }
    final doc = DiagramDocument.fromJson(row.documentJson);
    _row = row;
    _doc = doc;
    _viewport = doc.viewport;
    _title.text = row.title;
    _canvasDark = ref.read(appSettingsProvider).canvasDark;
    setState(() {
      _loading = false;
      _savedAt = row.updatedAt;
    });
  }

  void _markDirty() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), _save);
    if (mounted) setState(() {});
  }

  void _pushHistory() {
    _undoStack.add(
      jsonEncode({'document': _doc.toJson(), 'viewport': _viewport.toJson()}),
    );
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  Future<void> _save() async {
    final row = _row;
    if (row == null || _saving) return;
    _debounce?.cancel();
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final doc = _doc.copyWith(title: _title.text, viewport: _viewport);
      String? thumbnail = row.thumbnailBase64;
      try {
        final image = await DiagramExportService.renderImage(doc, scale: 0.6);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (data != null) {
          thumbnail = base64Encode(data.buffer.asUint8List());
        }
      } catch (_) {}
      final updated = await ref
          .read(diagramsRepositoryProvider)
          .save(
            row,
            title: _title.text,
            documentJson: doc.toJson(),
            thumbnailBase64: thumbnail,
            searchText: doc.searchableText,
          );
      if (!mounted) return;
      setState(() {
        _row = updated;
        _doc = doc;
        _savedAt = updated.updatedAt;
        _dirty = false;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'Could not save diagram: $error', error: true);
    }
  }

  void _flush() {
    final row = _row;
    if (!_dirty || row == null) return;
    _dirty = false;
    final doc = _doc.copyWith(title: _title.text, viewport: _viewport);
    unawaited(
      ref
          .read(diagramsRepositoryProvider)
          .save(
            row,
            title: _title.text,
            documentJson: doc.toJson(),
            searchText: doc.searchableText,
          ),
    );
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(
      jsonEncode({'document': _doc.toJson(), 'viewport': _viewport.toJson()}),
    );
    _restoreSnapshot(_undoStack.removeLast());
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(
      jsonEncode({'document': _doc.toJson(), 'viewport': _viewport.toJson()}),
    );
    _restoreSnapshot(_redoStack.removeLast());
  }

  void _restoreSnapshot(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final doc = DiagramDocument.fromJson(json['document'] as String);
      final viewport = DiagramViewport.fromJson(
        (json['viewport'] as Map?)?.cast<String, dynamic>(),
      );
      setState(() {
        _doc = doc;
        _viewport = viewport;
        _title.text = doc.title;
        _selectedShapeId = null;
        _selectedConnectorId = null;
      });
      _markDirty();
    } catch (_) {}
  }

  Offset _toScene(Offset local) => Offset(
    (local.dx - _viewport.dx) / _viewport.scale,
    (local.dy - _viewport.dy) / _viewport.scale,
  );

  DiagramShape? _hitShape(Offset scene) {
    for (final shape in _doc.shapes.reversed) {
      if (shape.contains(scene)) return shape;
    }
    return null;
  }

  DiagramShape? get _selectedShape =>
      _selectedShapeId == null ? null : _doc.shapeById(_selectedShapeId!);

  DiagramConnector? get _selectedConnector {
    if (_selectedConnectorId == null) return null;
    for (final connector in _doc.connectors) {
      if (connector.id == _selectedConnectorId) return connector;
    }
    return null;
  }

  void _selectShape(DiagramShape? shape) {
    setState(() {
      _selectedShapeId = shape?.id;
      _selectedConnectorId = null;
    });
  }

  void _handleTap(Offset local) {
    final scene = _toScene(local);
    final type = _shapeTypeForTool(_tool);

    if (_tool == _Tool.connector) {
      final hit = _hitShape(scene);
      if (hit == null) return;
      if (_connectFromId == null) {
        setState(() => _connectFromId = hit.id);
        showAppSnack(context, 'Now tap the second shape.');
      } else if (_connectFromId != hit.id) {
        _pushHistory();
        final connector = DiagramConnector(
          id: const Uuid().v4(),
          fromId: _connectFromId!,
          toId: hit.id,
        );
        _doc.connectors.add(connector);
        setState(() {
          _connectFromId = null;
          _selectedConnectorId = connector.id;
          _selectedShapeId = null;
          _tool = _Tool.select;
        });
        _markDirty();
      }
      return;
    }

    if (type != null) {
      _pushHistory();
      final size = _defaultSize(type);
      final shape = DiagramShape(
        id: const Uuid().v4(),
        type: type,
        x: scene.dx - size.width / 2,
        y: scene.dy - size.height / 2,
        width: size.width,
        height: size.height,
        label: _defaultLabel(type),
        style: _defaultStyle(type),
      );
      _doc.shapes.add(shape);
      setState(() {
        _selectedShapeId = shape.id;
        _selectedConnectorId = null;
        _tool = _Tool.select;
      });
      _markDirty();
      return;
    }

    final hit = _hitShape(scene);
    _selectShape(hit);
  }

  Size _defaultSize(DiagramShapeType type) => switch (type) {
    DiagramShapeType.text => const Size(220, 44),
    DiagramShapeType.sticky => const Size(170, 140),
    DiagramShapeType.note => const Size(170, 120),
    DiagramShapeType.ellipse || DiagramShapeType.user => const Size(150, 150),
    DiagramShapeType.diamond => const Size(170, 120),
    _ => const Size(160, 90),
  };

  String _defaultLabel(DiagramShapeType type) => switch (type) {
    DiagramShapeType.text => 'Text',
    DiagramShapeType.sticky => 'Note',
    DiagramShapeType.server => 'Server',
    DiagramShapeType.database => 'Database',
    DiagramShapeType.sqlServer => 'SQL Server',
    DiagramShapeType.firewall => 'Firewall',
    DiagramShapeType.cloud => 'Internet',
    DiagramShapeType.router => 'Router',
    DiagramShapeType.networkSwitch => 'Switch',
    DiagramShapeType.loadBalancer => 'Load Balancer',
    DiagramShapeType.storage => 'Storage',
    DiagramShapeType.nextcloud => 'Nextcloud',
    _ => '',
  };

  DiagramStyle _defaultStyle(DiagramShapeType type) {
    if (type == DiagramShapeType.text) {
      return const DiagramStyle(
        fillColor: '#00000000',
        strokeColor: '#00000000',
        strokeWidth: 0,
      );
    }
    if (type == DiagramShapeType.sticky) {
      return const DiagramStyle(fillColor: '#FFE9A8', strokeColor: '#C9A227');
    }
    return const DiagramStyle();
  }

  void _handlePanStart(Offset local) {
    final scene = _toScene(local);
    if (_tool == _Tool.pan) {
      _dragStart = local;
      return;
    }
    final hit = _hitShape(scene);
    if (hit != null && !hit.locked) {
      _selectShape(hit);
      _dragShape = hit;
      _dragStart = scene;
      _dragOrigin = Offset(hit.x, hit.y);
      _dragMoved = false;
    } else {
      _dragShape = null;
      _dragStart = local;
      _selectShape(null);
    }
  }

  void _handlePanUpdate(Offset local, Offset delta) {
    if (_tool == _Tool.pan || _dragShape == null) {
      setState(() {
        _viewport = _viewport.copyWith(
          dx: _viewport.dx + delta.dx,
          dy: _viewport.dy + delta.dy,
        );
      });
      return;
    }
    final scene = _toScene(local);
    final target = _dragOrigin + (scene - _dragStart);
    if (!_dragMoved) {
      _pushHistory();
      _dragMoved = true;
    }
    setState(() {
      _dragShape!.x = target.dx;
      _dragShape!.y = target.dy;
    });
  }

  void _handlePanEnd() {
    if (_dragShape != null && _dragMoved) _markDirty();
    _dragShape = null;
    _dragMoved = false;
  }

  void _zoomAt(Offset local, double factor) {
    final scene = _toScene(local);
    final scale = (_viewport.scale * factor).clamp(0.2, 3.0);
    setState(() {
      _viewport = DiagramViewport(
        dx: local.dx - scene.dx * scale,
        dy: local.dy - scene.dy * scale,
        scale: scale,
      );
    });
  }

  void _fitToScreen() {
    if (_doc.shapes.isEmpty) {
      setState(() {
        _viewport = _viewport.copyWith(dx: 80, dy: 80, scale: 1);
      });
      return;
    }
    final bounds = DiagramExportService.documentBounds(_doc).inflate(60);
    final size = _canvasKey.currentContext?.size ?? const Size(900, 600);
    final scale =
        (size.width / bounds.width < size.height / bounds.height
                ? size.width / bounds.width
                : size.height / bounds.height)
            .clamp(0.2, 1.5);
    setState(() {
      _viewport = DiagramViewport(
        dx: -bounds.left * scale + (size.width - bounds.width * scale) / 2,
        dy: -bounds.top * scale + (size.height - bounds.height * scale) / 2,
        scale: scale,
      );
    });
  }

  void _deleteSelection() {
    final shape = _selectedShape;
    final connector = _selectedConnector;
    if (shape == null && connector == null) return;
    _pushHistory();
    if (shape != null) {
      _doc.shapes.removeWhere((s) => s.id == shape.id);
      _doc.connectors.removeWhere(
        (c) => c.fromId == shape.id || c.toId == shape.id,
      );
      _selectedShapeId = null;
    }
    if (connector != null) {
      _doc.connectors.removeWhere((c) => c.id == connector.id);
      _selectedConnectorId = null;
    }
    setState(() {});
    _markDirty();
  }

  void _duplicateSelection() {
    final shape = _selectedShape;
    if (shape == null) return;
    _pushHistory();
    final copy = shape.copyWith(
      id: const Uuid().v4(),
      x: shape.x + 24,
      y: shape.y + 24,
      locked: false,
    );
    _doc.shapes.add(copy);
    setState(() {
      _selectedShapeId = copy.id;
      _selectedConnectorId = null;
    });
    _markDirty();
  }

  void _bringToFront() {
    final shape = _selectedShape;
    if (shape == null) return;
    _pushHistory();
    _doc.shapes.remove(shape);
    _doc.shapes.add(shape);
    setState(() {});
    _markDirty();
  }

  void _sendToBack() {
    final shape = _selectedShape;
    if (shape == null) return;
    _pushHistory();
    _doc.shapes.remove(shape);
    _doc.shapes.insert(0, shape);
    setState(() {});
    _markDirty();
  }

  Future<void> _editLabel(DiagramShape shape) async {
    final controller = TextEditingController(text: shape.label);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          minLines: 1,
          decoration: const InputDecoration(
            hintText: 'Label shown on the shape',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (result == null) return;
    _pushHistory();
    setState(() => shape.label = result);
    _markDirty();
  }

  Future<void> _deleteDiagram() async {
    final row = _row;
    if (row == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Move to trash?',
      message: '"${row.title}" can be restored from Trash for 30 days.',
      confirmLabel: 'Move to trash',
      destructive: true,
    );
    if (!ok) return;
    _dirty = false;
    await ref.read(diagramsRepositoryProvider).softDelete(row.id);
    if (mounted) context.go('/diagrams');
  }

  Future<void> _export(String format) async {
    try {
      List<int> bytes;
      String extension;
      switch (format) {
        case 'svg':
          bytes = utf8.encode(
            DiagramExportService.svg(
              _doc.copyWith(title: _title.text),
              dark: _canvasDark,
            ),
          );
          extension = 'svg';
        case 'pdf':
          bytes = await DiagramExportService.pdf(
            _doc.copyWith(title: _title.text),
            dark: _canvasDark,
          );
          extension = 'pdf';
        default:
          bytes = await DiagramExportService.png(
            _doc.copyWith(title: _title.text),
            scale: 2,
            dark: _canvasDark,
          );
          extension = 'png';
      }
      await FilePicker.saveFile(
        dialogTitle: 'Export diagram',
        fileName:
            '${_title.text.replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '').trim().isEmpty ? 'diagram' : _title.text.replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '').trim()}.$extension',
        bytes: Uint8List.fromList(bytes),
      );
      if (mounted) showAppSnack(context, 'Diagram exported.');
    } catch (error) {
      if (mounted) showAppSnack(context, 'Export failed: $error', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _row == null) {
      return EmptyState(
        icon: Icons.account_tree_outlined,
        title: 'Diagram unavailable',
        message: _error ?? 'The diagram could not be opened.',
        action: TextButton(
          onPressed: () => context.go('/diagrams'),
          child: const Text('Back to diagrams'),
        ),
      );
    }

    final wide = MediaQuery.sizeOf(context).width > 1100;
    final showInspector = wide && _inspectorOpen;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _redo,
        const SingleActivator(LogicalKeyboardKey.keyD, control: true):
            _duplicateSelection,
        const SingleActivator(LogicalKeyboardKey.delete): _deleteSelection,
        const SingleActivator(LogicalKeyboardKey.backspace): _deleteSelection,
        const SingleActivator(LogicalKeyboardKey.escape): () => setState(() {
          _tool = _Tool.select;
          _selectedShapeId = null;
          _selectedConnectorId = null;
          _connectFromId = null;
        }),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopBar(context),
            const Divider(height: 1),
            _buildToolBar(context),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildCanvas(context)),
                  if (showInspector) ...[
                    const VerticalDivider(width: 1),
                    SizedBox(width: 280, child: _buildInspector(context)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back to diagrams',
            onPressed: () => context.go('/diagrams'),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 260,
            child: TextField(
              controller: _title,
              onChanged: (_) => _markDirty(),
              style: context.theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                hintText: 'Diagram title',
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SavedIndicator(savedAt: _savedAt),
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Undo (Ctrl+Z)',
            onPressed: _undoStack.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Redo (Ctrl+Shift+Z)',
            onPressed: _redoStack.isEmpty ? null : _redo,
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            tooltip: _showGrid ? 'Hide grid' : 'Show grid',
            onPressed: () => setState(() => _showGrid = !_showGrid),
            icon: Icon(_showGrid ? Icons.grid_on : Icons.grid_off),
          ),
          IconButton(
            tooltip: _canvasDark ? 'Light canvas' : 'Dark canvas',
            onPressed: () {
              setState(() => _canvasDark = !_canvasDark);
              ref.read(appSettingsProvider.notifier).setCanvasDark(_canvasDark);
            },
            icon: Icon(_canvasDark ? Icons.light_mode : Icons.dark_mode),
          ),
          IconButton(
            tooltip: 'Fit to screen',
            onPressed: _fitToScreen,
            icon: const Icon(Icons.fit_screen),
          ),
          PopupMenuButton<String>(
            tooltip: 'Export',
            icon: const Icon(Icons.ios_share),
            onSelected: _export,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'png', child: Text('Export PNG')),
              PopupMenuItem(value: 'svg', child: Text('Export SVG')),
              PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
            ],
          ),
          IconButton(
            tooltip: 'Delete diagram',
            onPressed: _deleteDiagram,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Widget _buildToolBar(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              children: [
                _toolButton(_Tool.select, Icons.near_me_outlined, 'Select'),
                _toolButton(_Tool.pan, Icons.pan_tool_outlined, 'Pan'),
                _toolButton(_Tool.connector, Icons.timeline, 'Connect'),
                const VerticalDivider(width: 16, indent: 8, endIndent: 8),
                _toolButton(_Tool.rectangle, Icons.crop_square, 'Rectangle'),
                _toolButton(_Tool.ellipse, Icons.circle_outlined, 'Ellipse'),
                _toolButton(_Tool.diamond, Icons.change_history, 'Diamond'),
                _toolButton(_Tool.text, Icons.text_fields, 'Text'),
                _toolButton(
                  _Tool.sticky,
                  Icons.sticky_note_2_outlined,
                  'Sticky',
                ),
                const VerticalDivider(width: 16, indent: 8, endIndent: 8),
                _toolButton(_Tool.server, Icons.dns_outlined, 'Server'),
                _toolButton(
                  _Tool.sqlServer,
                  Icons.storage_rounded,
                  'SQL Server',
                ),
                _toolButton(_Tool.database, Icons.storage_outlined, 'Database'),
                _toolButton(
                  _Tool.firewall,
                  Icons.security_outlined,
                  'Firewall',
                ),
                _toolButton(_Tool.cloud, Icons.cloud_outlined, 'Internet'),
                _toolButton(_Tool.router, Icons.router_outlined, 'Router'),
                _toolButton(_Tool.networkSwitch, Icons.hub_outlined, 'Switch'),
                _toolButton(_Tool.loadBalancer, Icons.alt_route, 'LB'),
                _toolButton(_Tool.storage, Icons.save_outlined, 'Storage'),
                _toolButton(
                  _Tool.nextcloud,
                  Icons.cloud_queue_outlined,
                  'Cloud',
                ),
              ],
            ),
          ),
          if (MediaQuery.sizeOf(context).width <= 1100)
            IconButton(
              tooltip: 'Inspector',
              onPressed: () => _showInspectorSheet(context),
              icon: const Icon(Icons.tune),
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _toolButton(_Tool tool, IconData icon, String label) {
    final selected = _tool == tool;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() {
            _tool = tool;
            _connectFromId = null;
          }),
          child: Container(
            width: 40,
            height: 38,
            decoration: BoxDecoration(
              color: selected
                  ? BrandColors.brass.withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 19,
              color: selected ? BrandColors.brass : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas(BuildContext context) {
    return Stack(
      key: _canvasKey,
      children: [
        Positioned.fill(
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                if (HardwareKeyboard.instance.isControlPressed ||
                    HardwareKeyboard.instance.isMetaPressed) {
                  _zoomAt(
                    event.localPosition,
                    event.scrollDelta.dy > 0 ? 0.9 : 1.1,
                  );
                } else {
                  setState(() {
                    _viewport = _viewport.copyWith(
                      dx: _viewport.dx - event.scrollDelta.dx,
                      dy: _viewport.dy - event.scrollDelta.dy,
                    );
                  });
                }
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => _handleTap(details.localPosition),
              onDoubleTapDown: (details) {
                final hit = _hitShape(_toScene(details.localPosition));
                if (hit != null) _editLabel(hit);
              },
              onPanStart: (details) => _handlePanStart(details.localPosition),
              onPanUpdate: (details) =>
                  _handlePanUpdate(details.localPosition, details.delta),
              onPanEnd: (_) => _handlePanEnd(),
              child: MouseRegion(
                cursor: _tool == _Tool.pan
                    ? SystemMouseCursors.grab
                    : _shapeTypeForTool(_tool) != null
                    ? SystemMouseCursors.precise
                    : SystemMouseCursors.basic,
                child: CustomPaint(
                  painter: DiagramPainter(
                    document: _doc,
                    viewport: _viewport,
                    selectedShapeId: _selectedShapeId,
                    selectedConnectorId: _selectedConnectorId,
                    showGrid: _showGrid,
                    dark: _canvasDark,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
        if (_doc.shapes.isEmpty)
          IgnorePointer(
            child: Center(
              child: Text(
                'Pick a shape from the toolbar and tap the canvas.',
                style: context.theme.textTheme.bodyMedium?.copyWith(
                  color: (_canvasDark ? Colors.white : Colors.black).withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (_canvasDark ? Colors.black : Colors.white).withValues(
                alpha: 0.75,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (_canvasDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.1,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _zoomAt(
                    Offset(
                      MediaQuery.sizeOf(context).width / 2,
                      MediaQuery.sizeOf(context).height / 2,
                    ),
                    0.9,
                  ),
                  icon: const Icon(Icons.remove, size: 16),
                ),
                Text(
                  '${(_viewport.scale * 100).round()}%',
                  style: const TextStyle(fontSize: 11),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _zoomAt(
                    Offset(
                      MediaQuery.sizeOf(context).width / 2,
                      MediaQuery.sizeOf(context).height / 2,
                    ),
                    1.1,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                ),
              ],
            ),
          ),
        ),
        if (_tool == _Tool.connector)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: BrandColors.brass,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _connectFromId == null
                      ? 'Tap the first shape'
                      : 'Tap the second shape',
                  style: const TextStyle(
                    color: BrandColors.charcoal,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInspector(BuildContext context) {
    final shape = _selectedShape;
    final connector = _selectedConnector;
    if (shape == null && connector == null) {
      return ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text(
            'Inspector',
            style: context.theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a shape or connector to edit its label, style and metadata.',
            style: context.theme.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const Divider(height: 28),
          Text(
            'Canvas',
            style: context.theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Show grid'),
            value: _showGrid,
            onChanged: (value) => setState(() => _showGrid = value),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Dark canvas'),
            value: _canvasDark,
            onChanged: (value) {
              setState(() => _canvasDark = value);
              ref.read(appSettingsProvider.notifier).setCanvasDark(value);
            },
          ),
          const Divider(height: 28),
          Text(
            'Shortcuts',
            style: context.theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ctrl+S save · Ctrl+Z undo · Ctrl+D duplicate\nDelete removes · Esc deselects',
            style: TextStyle(fontSize: 11, height: 1.6),
          ),
        ],
      );
    }
    if (connector != null) {
      return _ConnectorInspector(
        key: ValueKey(connector.id),
        connector: connector,
        onChanged: () {
          setState(() {});
          _markDirty();
        },
        onDelete: _deleteSelection,
      );
    }
    return _ShapeInspector(
      key: ValueKey(shape!.id),
      shape: shape,
      onChanged: () {
        setState(() {});
        _markDirty();
      },
      onDelete: _deleteSelection,
      onDuplicate: _duplicateSelection,
      onBringToFront: _bringToFront,
      onSendToBack: _sendToBack,
      onEditLabel: () => _editLabel(shape),
      onPushHistory: _pushHistory,
    );
  }

  void _showInspectorSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: _buildInspector(context),
      ),
    );
  }
}

class _ShapeInspector extends StatefulWidget {
  const _ShapeInspector({
    super.key,
    required this.shape,
    required this.onChanged,
    required this.onDelete,
    required this.onDuplicate,
    required this.onBringToFront,
    required this.onSendToBack,
    required this.onEditLabel,
    required this.onPushHistory,
  });

  final DiagramShape shape;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onBringToFront;
  final VoidCallback onSendToBack;
  final VoidCallback onEditLabel;
  final VoidCallback onPushHistory;

  @override
  State<_ShapeInspector> createState() => _ShapeInspectorState();
}

class _ShapeInspectorState extends State<_ShapeInspector> {
  late final TextEditingController _label;
  late final TextEditingController _ip;
  late final TextEditingController _port;
  late final TextEditingController _hostname;
  late final TextEditingController _url;
  late final TextEditingController _connection;

  @override
  void initState() {
    super.initState();
    final shape = widget.shape;
    _label = TextEditingController(text: shape.label);
    _ip = TextEditingController(text: shape.metadata.ip);
    _port = TextEditingController(text: shape.metadata.port);
    _hostname = TextEditingController(text: shape.metadata.hostname);
    _url = TextEditingController(text: shape.metadata.url);
    _connection = TextEditingController(text: shape.metadata.connectionString);
  }

  @override
  void dispose() {
    _label.dispose();
    _ip.dispose();
    _port.dispose();
    _hostname.dispose();
    _url.dispose();
    _connection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shape = widget.shape;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            const Icon(Icons.tune, size: 18, color: BrandColors.brass),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                shape.type.name,
                style: context.theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: widget.onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _field(
          'Label',
          _label,
          maxLines: 2,
          onChanged: (value) {
            shape.label = value;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Style',
          style: context.theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        _colorRow('Fill', shape.style.fillColor, (value) {
          shape.style = shape.style.copyWith(fillColor: value);
          widget.onChanged();
        }),
        const SizedBox(height: 6),
        _colorRow('Stroke', shape.style.strokeColor, (value) {
          shape.style = shape.style.copyWith(strokeColor: value);
          widget.onChanged();
        }),
        const SizedBox(height: 6),
        _colorRow('Text', shape.style.textColor, (value) {
          shape.style = shape.style.copyWith(textColor: value);
          widget.onChanged();
        }),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _slider('Stroke', shape.style.strokeWidth, 0, 8, (value) {
                shape.style = shape.style.copyWith(strokeWidth: value);
                widget.onChanged();
              }),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _slider('Font', shape.style.fontSize, 8, 40, (value) {
                shape.style = shape.style.copyWith(fontSize: value);
                widget.onChanged();
              }),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _slider('Radius', shape.style.cornerRadius, 0, 40, (
                value,
              ) {
                shape.style = shape.style.copyWith(cornerRadius: value);
                widget.onChanged();
              }),
            ),
          ],
        ),
        Wrap(
          spacing: 4,
          children: [
            _toggleChip('Dashed', shape.style.dashed, (value) {
              shape.style = shape.style.copyWith(dashed: value);
              widget.onChanged();
            }),
            _toggleChip('Shadow', shape.style.shadow, (value) {
              shape.style = shape.style.copyWith(shadow: value);
              widget.onChanged();
            }),
            _toggleChip('Locked', shape.locked, (value) {
              shape.locked = value;
              widget.onChanged();
            }),
          ],
        ),
        const Divider(height: 24),
        Text(
          'Metadata',
          style: context.theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        _field(
          'IP address',
          _ip,
          onChanged: (value) {
            shape.metadata = shape.metadata.copyWith(ip: value);
            widget.onChanged();
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _field(
                'Port',
                _port,
                onChanged: (value) {
                  shape.metadata = shape.metadata.copyWith(port: value);
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _field(
                'Hostname',
                _hostname,
                onChanged: (value) {
                  shape.metadata = shape.metadata.copyWith(hostname: value);
                  widget.onChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _field(
          'URL',
          _url,
          onChanged: (value) {
            shape.metadata = shape.metadata.copyWith(url: value);
            widget.onChanged();
          },
        ),
        const SizedBox(height: 8),
        _field(
          'Connection string',
          _connection,
          maxLines: 2,
          onChanged: (value) {
            shape.metadata = shape.metadata.copyWith(connectionString: value);
            widget.onChanged();
          },
        ),
        const Divider(height: 24),
        Text(
          'Position & size',
          style: context.theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'x ${shape.x.round()} · y ${shape.y.round()} · ${shape.width.round()}×${shape.height.round()}',
          style: const TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: widget.onEditLabel,
              icon: const Icon(Icons.text_fields, size: 15),
              label: const Text('Label'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onDuplicate,
              icon: const Icon(Icons.copy, size: 15),
              label: const Text('Duplicate'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onBringToFront,
              icon: const Icon(Icons.flip_to_front, size: 15),
              label: const Text('Front'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onSendToBack,
              icon: const Icon(Icons.flip_to_back, size: 15),
              label: const Text('Back'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _colorRow(
    String label,
    String current,
    ValueChanged<String> onChanged,
  ) {
    const colors = [
      '#F4E9D4',
      '#E8D3AE',
      '#D9B26A',
      '#FFFFFF',
      '#DCE9F5',
      '#D6F0DD',
      '#F8D7DA',
      '#E5E7EB',
      '#3E3630',
      '#8A6A31',
    ];
    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
        Expanded(
          child: Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final color in colors)
                GestureDetector(
                  onTap: () => onChanged(color),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: DiagramStyle.color(color),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: current.toUpperCase() == color.toUpperCase()
                            ? BrandColors.brass
                            : Colors.black12,
                        width: current.toUpperCase() == color.toUpperCase()
                            ? 2
                            : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(
            value.toStringAsFixed(0),
            style: const TextStyle(fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _toggleChip(String label, bool value, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      selected: value,
      visualDensity: VisualDensity.compact,
      onSelected: onChanged,
    );
  }
}

class _ConnectorInspector extends StatefulWidget {
  const _ConnectorInspector({
    super.key,
    required this.connector,
    required this.onChanged,
    required this.onDelete,
  });

  final DiagramConnector connector;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<_ConnectorInspector> createState() => _ConnectorInspectorState();
}

class _ConnectorInspectorState extends State<_ConnectorInspector> {
  late final TextEditingController _label;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.connector.label);
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connector = widget.connector;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            const Icon(Icons.timeline, size: 18, color: BrandColors.brass),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Connector',
                style: context.theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: widget.onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _label,
          decoration: const InputDecoration(
            labelText: 'Label',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            connector.label = value;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ConnectorKind>(
          initialValue: connector.kind,
          decoration: const InputDecoration(
            labelText: 'Route',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final kind in ConnectorKind.values)
              DropdownMenuItem(value: kind, child: Text(kind.name)),
          ],
          onChanged: (value) {
            connector.kind = value ?? connector.kind;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Dashed'),
          value: connector.dashed,
          onChanged: (value) {
            connector.dashed = value;
            widget.onChanged();
          },
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Arrow at end'),
          value: connector.arrowEnd,
          onChanged: (value) {
            connector.arrowEnd = value;
            widget.onChanged();
          },
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Arrow at start'),
          value: connector.arrowStart,
          onChanged: (value) {
            connector.arrowStart = value;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Width', style: TextStyle(fontSize: 11)),
            Expanded(
              child: Slider(
                value: connector.strokeWidth.clamp(1, 8).toDouble(),
                min: 1,
                max: 8,
                onChanged: (value) {
                  connector.strokeWidth = value;
                  widget.onChanged();
                },
              ),
            ),
          ],
        ),
        Text(
          'Stroke ${connector.strokeColor}',
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }
}
