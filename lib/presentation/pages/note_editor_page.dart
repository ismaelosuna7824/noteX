import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../widgets/editor_text_controls.dart';

/// Rich text note editor with auto-save.
///
/// Save indicator logic:
///   1. A 500 ms poller compares the current editor content against the
///      previous snapshot.  If different → user edited → show "Saving…".
///   2. A 3 s debounce fires after the last detected edit → [forceSave].
///   3. On success → show "Saved" for 2 s → hide.
///
/// Why polling instead of `document.changes`?
///   QuillEditor emits phantom change events on widget rebuilds triggered by
///   `notifyListeners()`.  Polling is immune to that — it only reacts when the
///   serialized content actually differs.
class NoteEditorPage extends StatefulWidget {
  final AppState appState;
  final ThemeState themeState;

  const NoteEditorPage({
    super.key,
    required this.appState,
    required this.themeState,
  });

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late QuillController _quillController;
  late TextEditingController _titleController;
  late FocusNode _editorFocusNode;
  String? _loadedNoteId;

  // ignore: experimental_member_use
  static final _controllerConfig = QuillControllerConfig(
    // ignore: experimental_member_use
    clipboardConfig: QuillClipboardConfig(
      // ignore: experimental_member_use
      enableExternalRichPaste: false,
    ),
  );

  // ── Save indicator ────────────────────────────────────────────────────
  // ValueNotifier so only the chip rebuilds, never the whole widget tree.
  final ValueNotifier<String> _saveStatus = ValueNotifier('');
  Timer? _debounce; // 3 s after last edit → save
  Timer? _hideTimer; // 2 s after save → hide "Saved"
  Timer? _editPoller; // 500 ms periodic edit detector

  // Snapshots used by the poller to detect real edits.
  String _prevContent = '';
  String _prevTitle = '';
  int _prevDocLength = 0;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _editorFocusNode = FocusNode();
    _titleController = TextEditingController();
    _quillController = QuillController.basic(config: _controllerConfig);
    _loadNote();
  }

  @override
  void didUpdateWidget(covariant NoteEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.appState.currentNote?.id != _loadedNoteId) {
      _loadNote();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hideTimer?.cancel();
    _editPoller?.cancel();

    final note = widget.appState.currentNote;
    if (note != null) {
      widget.appState.autoSaveService.forceSave(
        noteId: note.id,
        title: _titleController.text,
        content: _serializeContent(),
      );
    }
    widget.appState.autoSaveService.unwatch();

    _quillController.dispose();
    _titleController.dispose();
    _editorFocusNode.dispose();
    _saveStatus.dispose();
    super.dispose();
  }

  // ── Note loading ──────────────────────────────────────────────────────

  void _loadNote() {
    final note = widget.appState.currentNote;
    if (note == null || note.id == _loadedNoteId) return;
    _loadedNoteId = note.id;

    // Reset timers from previous note.
    _debounce?.cancel();
    _hideTimer?.cancel();
    _editPoller?.cancel();
    _saveStatus.value = '';

    _titleController.text = note.title;

    try {
      final delta = Document.fromJson(jsonDecode(note.content));
      _quillController = QuillController(
        document: delta,
        selection: const TextSelection.collapsed(offset: 0),
        config: _controllerConfig,
      );
    } catch (_) {
      _quillController = QuillController.basic(config: _controllerConfig);
    }

    // Initialize snapshots.
    _prevContent = _serializeContent();
    _prevTitle = _titleController.text;
    _prevDocLength = _quillController.document.length;

    // Register lazy getters for the service's periodic safety-net timer.
    widget.appState.autoSaveService.watch(
      noteId: note.id,
      getTitle: () => _titleController.text,
      getContent: _serializeContent,
    );

    // Start polling for edits — immune to phantom QuillEditor events.
    // 1.5 s is enough since the debounce save is 3 s after last edit.
    _editPoller = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _pollForEdits(),
    );
  }

  // ── Edit detection & save ─────────────────────────────────────────────

  String _serializeContent() =>
      jsonEncode(_quillController.document.toDelta().toJson());

  /// Called every 1.5 s — compares current state against previous snapshot.
  /// Uses a cheap length check first to skip expensive serialization when idle.
  void _pollForEdits() {
    final title = _titleController.text;
    final doc = _quillController.document;

    // Cheap check: if title and doc length are unchanged, likely no edit.
    if (title == _prevTitle && doc.length == _prevDocLength) return;

    final content = _serializeContent();
    if (content == _prevContent && title == _prevTitle) {
      _prevDocLength = doc.length;
      return;
    }
    _prevContent = content;
    _prevTitle = title;
    _prevDocLength = doc.length;
    _onUserEdit();
  }

  /// Called when a real edit is detected (by poller or title onChanged).
  void _onUserEdit() {
    _hideTimer?.cancel();
    _saveStatus.value = '';
    widget.appState.autoSaveService.markDirty();
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), _save);
  }

  /// Fires 3 s after the last detected edit.
  Future<void> _save() async {
    if (!mounted) return;
    final note = widget.appState.currentNote;
    if (note == null) return;

    final content = _serializeContent();
    final title = _titleController.text;

    final ok = await widget.appState.autoSaveService.forceSave(
      noteId: note.id,
      title: title,
      content: content,
    );

    if (!mounted) return;
    if (ok) {
      // Update snapshots so the poller won't re-detect saved content.
      _prevContent = content;
      _prevTitle = title;
      _saveStatus.value = 'saved';
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _saveStatus.value = '';
      });
    } else {
      _saveStatus.value = '';
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = widget.themeState.accentColor;
    final note = widget.appState.currentNote;

    const darkCard = Color(0xFF1A1A2E);
    final chipBg = isDark
        ? darkCard.withValues(alpha: 0.90)
        : Colors.white.withValues(alpha: 0.85);
    final chipBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.grey.shade200;
    final chipText = isDark ? Colors.white70 : Colors.grey.shade600;

    if (note == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.note_add_rounded,
              size: 64,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.20)
                  : Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No note selected',
              style: theme.textTheme.titleLarge?.copyWith(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.40)
                    : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                await widget.appState.createNewNote();
                if (context.mounted) setState(() => _loadNote());
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Note'),
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // Top controls row: title + toolbar
          Row(
            children: [
              // Title input
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    controller: _titleController,
                    onChanged: (_) {
                      _prevTitle = _titleController.text;
                      _onUserEdit();
                    },
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.grey.shade800,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Note title...',
                      filled: true,
                      fillColor: chipBg,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: chipBorder,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: accentColor.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      prefixIcon: Icon(
                        Icons.edit_note_rounded,
                        color: accentColor.withValues(alpha: 0.6),
                        size: 20,
                      ),
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white38 : Colors.grey.shade400,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Date chip
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: chipBorder,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: accentColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${note.updatedAt.month}/${note.updatedAt.day}/${note.updatedAt.year}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: chipText,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Sync status indicator
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: chipBorder,
                    width: 1,
                  ),
                ),
                child: Icon(
                  _getSyncIcon(note.syncStatus.name),
                  size: 18,
                  color: accentColor,
                ),
              ),

              // Save indicator — only shows "Saved", collapses when hidden
              ValueListenableBuilder<String>(
                valueListenable: _saveStatus,
                builder: (context, status, _) {
                  return AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    alignment: Alignment.centerLeft,
                    child: status == 'saved'
                        ? Container(
                            height: 44,
                            margin: const EdgeInsets.only(left: 8),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark
                                    ? Colors.green.withValues(alpha: 0.30)
                                    : Colors.green.shade200,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 14,
                                  color: isDark
                                      ? Colors.green.shade300
                                      : Colors.green.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Saved',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.green.shade300
                                        : Colors.green.shade600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Main editor area
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      // Quill toolbar
                      Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? darkCard.withValues(alpha: 0.90)
                              : Colors.white.withValues(alpha: 0.92),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                          border: Border.all(
                            color: chipBorder,
                            width: 1,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Focus(
                          canRequestFocus: false,
                          descendantsAreFocusable: false,
                          child: Row(
                            children: [
                              Expanded(
                                child: QuillSimpleToolbar(
                                  controller: _quillController,
                                  config: QuillSimpleToolbarConfig(
                                    showAlignmentButtons: true,
                                    showBackgroundColorButton: false,
                                    showClearFormat: false,
                                    showFontFamily: false,
                                    showFontSize: false,
                                    showInlineCode: true,
                                    showCodeBlock: true,
                                    showListCheck: true,
                                    multiRowsDisplay: false,
                                    decoration: const BoxDecoration(),
                                    buttonOptions:
                                        QuillSimpleToolbarButtonOptions(
                                      base: QuillToolbarBaseButtonOptions(
                                        iconTheme: QuillIconTheme(
                                          iconButtonSelectedData:
                                              IconButtonData(
                                            color: accentColor,
                                          ),
                                          iconButtonUnselectedData:
                                              IconButtonData(
                                            color:
                                                isDark ? Colors.white70 : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              EditorTextControls(
                                  themeState: widget.themeState),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                      ),

                      // Editor content
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? darkCard.withValues(alpha: 0.90)
                                : Colors.white,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(20),
                              bottomRight: Radius.circular(20),
                            ),
                            border: Border(
                              left: BorderSide(
                                color: chipBorder,
                                width: 1,
                              ),
                              right: BorderSide(
                                color: chipBorder,
                                width: 1,
                              ),
                              bottom: BorderSide(
                                color: chipBorder,
                                width: 1,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                    alpha: isDark ? 0.25 : 0.05),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(24),
                          child: QuillEditor.basic(
                            controller: _quillController,
                            focusNode: _editorFocusNode,
                            config: QuillEditorConfig(
                              placeholder: 'Start writing your thoughts...',
                              padding: const EdgeInsets.all(8),
                              expands: true,
                              textSelectionThemeData: TextSelectionThemeData(
                                cursorColor: accentColor,
                              ),
                              customStyles: _buildQuillStyles(isDark),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  DefaultStyles _buildQuillStyles(bool isDark) {
    final fontSize = widget.themeState.editorFontSize;
    final lh = widget.themeState.editorLineHeight;

    return DefaultStyles(
      placeHolder: DefaultTextBlockStyle(
        TextStyle(
          fontSize: fontSize,
          height: lh,
          color: isDark ? Colors.white38 : Colors.grey.shade400,
        ),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(6, 6),
        const VerticalSpacing(0, 0),
        null,
      ),
      paragraph: DefaultTextBlockStyle(
        TextStyle(
          fontSize: fontSize,
          height: lh,
          color: isDark ? Colors.white : Colors.grey.shade800,
        ),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(6, 6),
        const VerticalSpacing(0, 0),
        null,
      ),
      lists: DefaultListBlockStyle(
        TextStyle(
          fontSize: fontSize,
          height: lh,
          color: isDark ? Colors.white : Colors.grey.shade800,
        ),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(6, 6),
        const VerticalSpacing(0, 0),
        null,
        null,
      ),
      leading: DefaultTextBlockStyle(
        TextStyle(
          fontSize: fontSize,
          height: lh,
          color: isDark ? Colors.white : Colors.grey.shade800,
        ),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(0, 0),
        const VerticalSpacing(0, 0),
        null,
      ),
    );
  }

  IconData _getSyncIcon(String status) {
    switch (status) {
      case 'synced':
        return Icons.cloud_done_rounded;
      case 'pendingSync':
        return Icons.cloud_upload_rounded;
      case 'conflict':
        return Icons.warning_rounded;
      default:
        return Icons.cloud_off_rounded;
    }
  }
}
