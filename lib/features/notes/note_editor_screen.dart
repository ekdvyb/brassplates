import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../../widgets/common.dart';

final _noteAttachmentsProvider = StreamProvider.autoDispose
    .family<List<Attachment>, String>(
      (ref, noteId) =>
          ref.watch(attachmentsRepositoryProvider).watchFor('note', noteId),
    );

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

  Future<void> _addPictures() async {
    final note = _note;
    if (note == null) return;
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Attach pictures',
      type: FileType.image,
    );
    if (picked.isEmpty) return;
    var added = 0;
    for (final file in picked) {
      var path = file.path;
      if (path == null) {
        try {
          final bytes = await file.readAsBytes();
          final temp = File(
            '${Directory.systemTemp.path}${Platform.pathSeparator}${file.name}',
          );
          await temp.writeAsBytes(bytes, flush: true);
          path = temp.path;
        } catch (_) {
          continue;
        }
      }
      try {
        await ref
            .read(attachmentsRepositoryProvider)
            .addFile(
              entityType: 'note',
              entityId: note.id,
              sourcePath: path,
            );
        added++;
      } catch (error) {
        if (mounted) {
          showAppSnack(context, 'Could not attach ${file.name}: $error', error: true);
        }
      }
    }
    ref.invalidate(_noteAttachmentsProvider(note.id));
    if (added > 0 && mounted) {
      showAppSnack(context, added == 1 ? 'Picture attached.' : '$added pictures attached.');
    }
  }

  Future<void> _removePicture(Attachment attachment) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove picture?',
      message: 'The picture is deleted from this note and from the device.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(attachmentsRepositoryProvider).delete(attachment);
    ref.invalidate(_noteAttachmentsProvider(widget.noteId));
  }

  void _viewPicture(Attachment attachment) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.file(
                File(attachment.localPath),
                errorBuilder: (_, _, _) => const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('This picture is missing on disk.'),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton.filledTonal(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds one self-contained HTML file, with the pictures embedded, so the
  /// note can be emailed or shared and still show its images everywhere.
  Future<String?> _saveHtmlCopy() async {
    final note = _note;
    final controller = _controller;
    if (note == null || controller == null) return null;
    final attachments = await ref
        .read(attachmentsRepositoryProvider)
        .listFor('note', note.id);

    final body = StringBuffer();
    for (final paragraph in controller.document
        .toPlainText()
        .split(RegExp(r'\n+'))) {
      final trimmed = paragraph.trim();
      if (trimmed.isEmpty) continue;
      body.writeln('<p>${_escapeHtml(trimmed).replaceAll('\n', '<br>')}</p>');
    }
    for (final attachment in attachments) {
      try {
        final bytes = await File(attachment.localPath).readAsBytes();
        final data = base64Encode(bytes);
        body.writeln(
          '<figure><img src="data:${attachment.mimeType};base64,$data" '
          'alt="${_escapeHtml(attachment.fileName)}">'
          '<figcaption>${_escapeHtml(attachment.fileName)}</figcaption></figure>',
        );
      } catch (_) {
        // Skip a picture that is missing on disk.
      }
    }

    final html = '''<!doctype html>
<html><head><meta charset="utf-8">
<title>${_escapeHtml(_title.text)}</title>
<style>
body{font-family:system-ui,Segoe UI,Arial,sans-serif;max-width:760px;margin:40px auto;padding:0 20px;color:#1b1a18;line-height:1.55}
h1{font-size:30px;margin-bottom:4px}
.meta{color:#8a7a63;font-size:13px;margin-bottom:24px}
figure{margin:20px 0}
img{max-width:100%;border-radius:10px}
figcaption{color:#8a7a63;font-size:12px}
</style></head>
<body>
<h1>${_escapeHtml(_title.text)}</h1>
<div class="meta">BRASSPLATES · ${formatDateTime(note.updatedAt)}</div>
${body.toString()}
</body></html>'''.trim();

    final fileName =
        '${_safeFileName(_title.text.isEmpty ? 'note' : _title.text)}.html';
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Save note to share',
      fileName: fileName,
      mimeType: 'text/html',
      bytes: Uint8List.fromList(utf8.encode(html)),
    );
    if (saved == null) return null;
    return saved.scheme == 'file' ? saved.toFilePath() : saved.toString();
  }

  Future<void> _shareOrEmail({required bool email}) async {
    final controller = _controller;
    if (controller == null) return;
    String? path;
    try {
      path = await _saveHtmlCopy();
    } catch (error) {
      if (mounted) {
        showAppSnack(context, 'Could not save the note: $error', error: true);
      }
      return;
    }
    if (path == null) return;
    if (!email) {
      if (mounted) {
        showAppSnack(
          context,
          'Saved $path — send it with mail, chat or any app.',
        );
      }
      return;
    }

    final subjectText = _title.text.isEmpty
        ? 'Note from BRASSPLATES'
        : _title.text;
    final bodyText =
        '${controller.document.toPlainText()}\n\n'
        'The note with pictures is attached as ${path.split(Platform.pathSeparator).last}.';

    // On Linux, xdg-email opens the user's mail composer with the file
    // attached, so the pictures travel with the message.
    if (Platform.isLinux) {
      try {
        final result = await Process.run('xdg-email', [
          '--subject',
          subjectText,
          '--body',
          bodyText,
          '--attach',
          path,
        ]);
        if (result.exitCode == 0) {
          if (mounted) {
            showAppSnack(
              context,
              'Email draft opened with the note and pictures attached.',
            );
          }
          return;
        }
      } catch (_) {
        // Fall through to a plain mailto link.
      }
    }

    final subject = Uri.encodeComponent(subjectText);
    final body = Uri.encodeComponent(bodyText);
    final uri = Uri.parse('mailto:?subject=$subject&body=$body');
    if (!await launchUrl(uri) && mounted) {
      showAppSnack(
        context,
        'No email app found. The share file was saved to $path.',
        error: true,
      );
      return;
    }
    if (mounted) {
      showAppSnack(
        context,
        'Email draft opened. Attach ${path.split(Platform.pathSeparator).last} to include the pictures.',
      );
    }
  }

  String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _safeFileName(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9 _-]+'), '').trim().isEmpty
      ? 'note'
      : value.replaceAll(RegExp(r'[^A-Za-z0-9 _-]+'), '').trim();

  Widget _buildToolbar(bool compact) {
    final toolbar = quill.QuillSimpleToolbar(
      controller: _controller!,
      config: quill.QuillSimpleToolbarConfig(
        multiRowsDisplay: !compact,
        showFontFamily: true,
        showFontSize: true,
        showInlineCode: true,
        showSubscript: true,
        showSuperscript: true,
        showColorButton: true,
        showBackgroundColorButton: true,
        showClearFormat: true,
        showAlignmentButtons: !compact,
        showSearchButton: false,
        showUndo: true,
        showRedo: true,
      ),
    );
    if (!compact) return toolbar;
    // Narrow windows: keep every control reachable by scrolling sideways
    // instead of hiding the toolbar completely.
    return Container(
      height: 46,
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: toolbar,
      ),
    );
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
                  tooltip: 'Attach pictures',
                  onPressed: _addPictures,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
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
                      case 'email':
                        _shareOrEmail(email: true);
                      case 'share':
                        _shareOrEmail(email: false);
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
                      value: 'email',
                      child: Text('Email note'),
                    ),
                    PopupMenuItem(
                      value: 'share',
                      child: Text('Share / save copy with pictures'),
                    ),
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
                    _AttachmentStrip(
                      noteId: widget.noteId,
                      onAdd: _addPictures,
                      onView: _viewPicture,
                      onRemove: _removePicture,
                    ),
                    _buildToolbar(compact),
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

class _AttachmentStrip extends ConsumerWidget {
  const _AttachmentStrip({
    required this.noteId,
    required this.onAdd,
    required this.onView,
    required this.onRemove,
  });

  final String noteId;
  final Future<void> Function() onAdd;
  final void Function(Attachment attachment) onView;
  final Future<void> Function(Attachment attachment) onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(_noteAttachmentsProvider(noteId));
    return rows.maybeWhen(
      data: (attachments) {
        if (attachments.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            itemCount: attachments.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index == attachments.length) {
                return OutlinedButton.icon(
                  onPressed: () => onAdd(),
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                  label: const Text('Add'),
                );
              }
              final attachment = attachments[index];
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => onView(attachment),
                      child: Image.file(
                        File(attachment.localPath),
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 84,
                          height: 84,
                          color: context.colors.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton.filledTonal(
                      tooltip: 'Remove picture',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () => onRemove(attachment),
                      icon: const Icon(Icons.close, size: 14),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
