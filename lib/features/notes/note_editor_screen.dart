import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../widgets/common.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, required this.noteId});

  final String noteId;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  Note? _note;
  quill.QuillController? _controller;
  final _title = TextEditingController();
  final _tags = TextEditingController();
  final _editorFocus = FocusNode();
  Timer? _debounce;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  DateTime? _savedAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NoteEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId) {
      _teardown();
      _load();
    }
  }

  @override
  void dispose() {
    _teardown();
    _title.dispose();
    _tags.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  void _teardown() {
    _debounce?.cancel();
    _flush();
    _controller?.removeListener(_onDocumentChanged);
    _controller?.dispose();
    _controller = null;
    _note = null;
    _dirty = false;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final note = await ref.read(notesRepositoryProvider).byId(widget.noteId);
    if (!mounted) return;
    if (note == null) {
      setState(() {
        _loading = false;
        _error = 'This note no longer exists.';
      });
      return;
    }
    _note = note;
    _title.text = note.title;
    _tags.text = note.tagsCsv;
    _controller = quill.QuillController(
      document: _documentFor(note),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _controller!.addListener(_onDocumentChanged);
    setState(() {
      _loading = false;
      _savedAt = note.updatedAt;
      _dirty = false;
    });
  }

  quill.Document _documentFor(Note note) {
    if (note.contentDelta.trim().isEmpty) return quill.Document();
    try {
      final json = jsonDecode(note.contentDelta);
      if (json is List) return quill.Document.fromJson(json);
    } catch (_) {}
    return quill.Document()..insert(0, note.plainText);
  }

  void _onDocumentChanged() {
    _markDirty();
  }

  void _markDirty() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () => _persist());
    if (mounted) setState(() {});
  }

  void _flush() {
    final note = _note;
    final controller = _controller;
    if (!_dirty || note == null || controller == null) return;
    _dirty = false;
    unawaited(
      ref
          .read(notesRepositoryProvider)
          .save(
            note,
            title: _title.text,
            contentDelta: jsonEncode(controller.document.toDelta().toJson()),
            plainText: controller.document.toPlainText(),
            tagsCsv: _tags.text.trim(),
          ),
    );
  }

  Future<void> _persist({bool notify = true}) async {
    final note = _note;
    final controller = _controller;
    if (note == null || controller == null || _saving) return;
    _debounce?.cancel();
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final delta = jsonEncode(controller.document.toDelta().toJson());
      final plain = controller.document.toPlainText();
      final updated = await ref
          .read(notesRepositoryProvider)
          .save(
            note,
            title: _title.text,
            contentDelta: delta,
            plainText: plain,
            tagsCsv: _tags.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _note = updated;
        _savedAt = updated.updatedAt;
        _dirty = false;
        _saving = false;
      });
      if (notify) {
        // Saved silently; indicator updates.
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (notify) showAppSnack(context, 'Could not save: $error', error: true);
    }
  }

  Future<void> _togglePin() async {
    final note = _note;
    if (note == null) return;
    await ref.read(notesRepositoryProvider).togglePin(note);
    final refreshed = await ref.read(notesRepositoryProvider).byId(note.id);
    if (refreshed != null && mounted) setState(() => _note = refreshed);
  }

  Future<void> _delete() async {
    final note = _note;
    if (note == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Move to trash?',
      message: '"${note.title}" can be restored from Trash for 30 days.',
      confirmLabel: 'Move to trash',
      destructive: true,
    );
    if (!ok) return;
    _dirty = false;
    await ref.read(notesRepositoryProvider).softDelete(note.id);
    if (mounted) context.go('/notes');
  }

  Future<void> _showHistory() async {
    final note = _note;
    if (note == null) return;
    final revisions = await ref
        .read(notesRepositoryProvider)
        .revisions(note.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Version history'),
        content: SizedBox(
          width: 460,
          height: 420,
          child: revisions.isEmpty
              ? const Center(child: Text('No versions saved yet.'))
              : ListView.separated(
                  itemCount: revisions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final revision = revisions[index];
                    final data = decodeMap(revision.contentJson);
                    return ListTile(
                      dense: true,
                      title: Text('Version ${revision.version}'),
                      subtitle: Text(
                        '${formatDateTime(revision.createdAt)} · ${truncate((data['plainText'] as String? ?? '').replaceAll(RegExp(r'\s+'), ' '), 60)}',
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          await ref
                              .read(notesRepositoryProvider)
                              .restoreRevision(note.id, revision);
                          if (context.mounted) Navigator.pop(context);
                          _teardown();
                          await _load();
                          if (context.mounted) {
                            showAppSnack(context, 'Version restored.');
                          }
                        },
                        child: const Text('Restore'),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportMarkdown() async {
    final note = _note;
    final controller = _controller;
    if (note == null || controller == null) return;
    final body = controller.document.toPlainText();
    final markdown = '# ${_title.text}\n\n$body\n';
    try {
      await FilePicker.saveFile(
        dialogTitle: 'Export note as Markdown',
        fileName:
            '${_title.text.trim().isEmpty ? 'note' : _title.text.trim()}.md',
        bytes: Uint8List.fromList(utf8.encode(markdown)),
      );
      if (mounted) showAppSnack(context, 'Markdown exported.');
    } catch (error) {
      if (mounted) showAppSnack(context, 'Export failed: $error', error: true);
    }
  }

  Future<void> _copyMarkdown() async {
    final controller = _controller;
    if (controller == null) return;
    final markdown =
        '# ${_title.text}\n\n${controller.document.toPlainText()}\n';
    await Clipboard.setData(ClipboardData(text: markdown));
    if (mounted) showAppSnack(context, 'Markdown copied to clipboard.');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _note == null || _controller == null) {
      return EmptyState(
        icon: Icons.description_outlined,
        title: 'Note unavailable',
        message: _error ?? 'The note could not be opened.',
        action: TextButton(
          onPressed: () => context.go('/notes'),
          child: const Text('Back to notes'),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 900;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            _persist(),
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): () =>
            _exportMarkdown(),
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back to notes',
                  onPressed: () => context.go('/notes'),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 4),
                Expanded(child: SavedIndicator(savedAt: _savedAt)),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                IconButton(
                  tooltip: _note!.pinned ? 'Unpin' : 'Pin',
                  onPressed: _togglePin,
                  icon: Icon(
                    _note!.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    color: _note!.pinned ? BrandColors.brass : null,
                  ),
                ),
                IconButton(
                  tooltip: 'Version history',
                  onPressed: _showHistory,
                  icon: const Icon(Icons.history),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (value) {
                    switch (value) {
                      case 'export':
                        _exportMarkdown();
                      case 'copy':
                        _copyMarkdown();
                      case 'delete':
                        _delete();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'export',
                      child: Text('Export Markdown'),
                    ),
                    PopupMenuItem(value: 'copy', child: Text('Copy Markdown')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Move to trash'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                      child: TextField(
                        controller: _title,
                        onChanged: (_) => _markDirty(),
                        style: context.theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Note title',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: _tags,
                        onChanged: (_) => _markDirty(),
                        style: context.theme.textTheme.bodySmall,
                        decoration: const InputDecoration(
                          hintText: 'Tags (comma separated)',
                          prefixIcon: Icon(Icons.sell_outlined, size: 16),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (!compact)
                      quill.QuillSimpleToolbar(
                        controller: _controller!,
                        config: const quill.QuillSimpleToolbarConfig(
                          showFontFamily: false,
                          showFontSize: false,
                          showSubscript: false,
                          showSuperscript: false,
                          showSearchButton: false,
                          showInlineCode: false,
                          multiRowsDisplay: false,
                        ),
                      ),
                    const Divider(height: 1),
                    Expanded(
                      child: quill.QuillEditor.basic(
                        controller: _controller!,
                        focusNode: _editorFocus,
                        config: quill.QuillEditorConfig(
                          placeholder: 'Start writing…',
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
                          expands: true,
                          autoFocus: false,
                          customStyles: quill.DefaultStyles.getInstance(
                            context,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: context.colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  '${_controller!.document.toPlainText().trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length} words',
                  style: context.theme.textTheme.labelSmall?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const Spacer(),
                Text(
                  'Ctrl+S save · Ctrl+E export',
                  style: context.theme.textTheme.labelSmall?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
