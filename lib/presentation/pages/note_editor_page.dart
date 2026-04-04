import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/entities/note.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../state/security_state.dart';
import 'package:get_it/get_it.dart';
import '../widgets/editor_text_controls.dart';
import '../widgets/mention_overlay.dart';
import '../state/tiling_state.dart';
import '../widgets/tiling_layout.dart';

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
  final bool isZenMode;

  const NoteEditorPage({
    super.key,
    required this.appState,
    required this.themeState,
    this.isZenMode = false,
  });

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late QuillController _quillController;
  late TextEditingController _titleController;
  late FocusNode _editorFocusNode;
  String? _loadedNoteId;

  // ── Tiling state (singleton, persisted to disk) ─────────────────────
  TilingState get _tiling => GetIt.instance<TilingState>();


  // ignore: experimental_member_use
  static final _controllerConfig = QuillControllerConfig(
    // ignore: experimental_member_use
    clipboardConfig: QuillClipboardConfig(
      // ignore: experimental_member_use
      enableExternalRichPaste: false,
    ),
  );

  // ── Save indicator ────────────────────────────────────────────────────
  final ValueNotifier<String> _saveStatus = ValueNotifier('');
  Timer? _debounce;
  Timer? _hideTimer;
  Timer? _editPoller;

  // Snapshots for polling-based edit detection.
  // Why polling instead of document.changes?
  //   QuillEditor emits phantom change events on widget rebuilds triggered
  //   by notifyListeners(). Polling is immune to that — it only reacts
  //   when the serialized content actually differs.
  String _prevContent = '';
  String _prevTitle = '';
  int _prevDocLength = 0;

  // ── @mention overlay ───────────────────────────────────────────────
  OverlayEntry? _mentionOverlay;
  final GlobalKey _mentionKey = GlobalKey();
  String _mentionQuery = '';
  int _mentionStartOffset = -1;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _editorFocusNode = FocusNode();
    _titleController = TextEditingController();
    _quillController = QuillController.basic(config: _controllerConfig);
    _loadNote();
    // Register save callback so navigateToPage can flush before switching
    widget.appState.editorSaveCallback = _saveCurrentNote;
  }

  @override
  void didUpdateWidget(covariant NoteEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final note = widget.appState.currentNote;
    if (note == null) return;
    if (note.id != _loadedNoteId) {
      _loadNote();
      setState(() {});
    } else if (note.content != _prevContent) {
      // Same note but content changed (e.g. edited in notes list preview)
      _loadNote(force: true);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hideTimer?.cancel();
    _editPoller?.cancel();

    final note = widget.appState.currentNote;
    if (note != null && !_tiling.isActive) {
      widget.appState.autoSaveService.forceSave(
        noteId: note.id,
        title: _titleController.text,
        content: _serializeContent(),
      );
    }
    widget.appState.editorSaveCallback = null;
    widget.appState.autoSaveService.unwatch();
    _dismissMention();
    _quillController.dispose();
    _titleController.dispose();
    _editorFocusNode.dispose();
    _saveStatus.dispose();
    _lockPinController.dispose();
    _lockErrorNotifier.dispose();
    super.dispose();
  }

  // ── Note loading ──────────────────────────────────────────────────────

  void _loadNote({bool force = false}) {
    final note = widget.appState.currentNote;
    if (note == null) return;
    if (!force && note.id == _loadedNoteId) return;
    _loadedNoteId = note.id;

    _debounce?.cancel();
    _hideTimer?.cancel();
    _editPoller?.cancel();
    _saveStatus.value = '';

    _titleController.text = note.title;

    _quillController.removeListener(_checkForMention);
    _quillController.dispose();

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

    _quillController.addListener(_checkForMention);

    // Initialize snapshots
    _prevContent = _serializeContent();
    _prevTitle = _titleController.text;
    _prevDocLength = _quillController.document.length;

    // Register for auto-save service safety net
    widget.appState.autoSaveService.watch(
      noteId: note.id,
      getTitle: () => _titleController.text,
      getContent: _serializeContent,
    );

    // Polling-based edit detection (immune to phantom QuillEditor events)
    _editPoller = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _pollForEdits(),
    );
  }

  /// Save the current note content to DB. Called by AppState.navigateToPage.
  Future<void> _saveCurrentNote() async {
    // Don't save from the main editor when tiling is active —
    // tiling panels own the content and flushAll handles their saves.
    if (_tiling.isActive) return;
    final note = widget.appState.currentNote;
    if (note == null) return;
    await widget.appState.autoSaveService.forceSave(
      noteId: note.id,
      title: _titleController.text,
      content: _serializeContent(),
    );
  }

  // ── Edit detection & save ─────────────────────────────────────────────

  String _serializeContent() =>
      jsonEncode(_quillController.document.toDelta().toJson());

  /// Called every 1.5 s — compares current state against previous snapshot.
  void _pollForEdits() {
    final title = _titleController.text;
    final doc = _quillController.document;

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
    _debounce = Timer(const Duration(seconds: 2), _save);
  }

  /// Fires 2 s after the last detected edit.
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
      _prevContent = content;
      _prevTitle = title;
      _saveStatus.value = 'saved';
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _saveStatus.value = '';
      });
    }
  }

  // ── @mention helpers ──────────────────────────────────────────────────

  /// Called on every selection/content change to detect `@` mention trigger.
  void _checkForMention() {
    final sel = _quillController.selection;
    if (!sel.isCollapsed) {
      _dismissMention();
      return;
    }

    final offset = sel.baseOffset;
    if (offset <= 0) {
      _dismissMention();
      return;
    }

    // Check if cursor is inside an existing link — if so, skip
    final style = _quillController.getSelectionStyle();
    if (style.attributes.containsKey(Attribute.link.key)) {
      _dismissMention();
      return;
    }

    final text = _quillController.document.toPlainText();

    // Search backwards from cursor for `@`
    int atPos = -1;
    for (int i = offset - 1; i >= 0; i--) {
      final ch = text[i];
      if (ch == '@') {
        atPos = i;
        break;
      }
      if (ch == '\n' || ch == ' ') {
        break;
      }
    }

    if (atPos < 0) {
      _dismissMention();
      return;
    }

    // Check if the `@` itself is part of an existing link
    final atStyle = _quillController.document.collectStyle(atPos, 0);
    if (atStyle.attributes.containsKey(Attribute.link.key)) {
      _dismissMention();
      return;
    }

    // Must be at start of line or preceded by whitespace
    if (atPos > 0 && text[atPos - 1] != '\n' && text[atPos - 1] != ' ') {
      _dismissMention();
      return;
    }

    final query = text.substring(atPos + 1, offset);
    _mentionStartOffset = atPos;
    _mentionQuery = query;
    _showMentionOverlay();
  }

  void _showMentionOverlay() {
    _mentionOverlay?.remove();

    final overlay = Overlay.of(context);
    final editorBox = context.findRenderObject() as RenderBox?;
    if (editorBox == null) return;

    // Position overlay near the top of the editor area
    final editorPos = editorBox.localToGlobal(Offset.zero);

    _mentionOverlay = OverlayEntry(
      builder: (_) => Positioned(
        left: editorPos.dx + 40,
        top: editorPos.dy + 80,
        child: MentionOverlay(
          key: _mentionKey,
          notes: widget.appState.notes
              .where((n) => n.id != widget.appState.currentNote?.id)
              .toList(),
          query: _mentionQuery,
          onSelect: _onMentionSelected,
          onDismiss: _dismissMention,
          accentColor: widget.themeState.accentColor,
          bgColor: widget.themeState.editorBgColor,
          borderColor: widget.themeState.editorBorderColor,
          textColor: widget.themeState.editorTextColor,
          mutedColor: widget.themeState.editorMutedTextColor,
        ),
      ),
    );

    overlay.insert(_mentionOverlay!);
  }

  void _onMentionSelected(Note note) {
    final title = note.title.isEmpty ? 'Untitled' : note.title;
    final ctrl = _quillController;
    final linkText = '@$title';
    final startOffset = _mentionStartOffset;
    final cursorOffset = ctrl.selection.baseOffset;

    // Dismiss overlay first (but we already saved the offsets above)
    _mentionOverlay?.remove();
    _mentionOverlay = null;
    _mentionStartOffset = -1;
    _mentionQuery = '';

    if (startOffset < 0 || cursorOffset < startOffset) return;

    // Remove listener temporarily to avoid re-triggering mention detection
    ctrl.removeListener(_checkForMention);

    try {
      // Delete the `@query` text
      final deleteLength = cursorOffset - startOffset;
      if (deleteLength > 0) {
        ctrl.replaceText(startOffset, deleteLength, '', null);
      }

      // Insert the linked text
      ctrl.document.insert(startOffset, linkText);
      ctrl.document.format(
        startOffset,
        linkText.length,
        LinkAttribute('notex://${note.id}'),
      );

      // Insert a trailing space (unlinked)
      ctrl.document.insert(startOffset + linkText.length, ' ');

      // Move cursor after the space
      ctrl.updateSelection(
        TextSelection.collapsed(offset: startOffset + linkText.length + 1),
        ChangeSource.local,
      );
    } finally {
      ctrl.addListener(_checkForMention);
    }
  }

  void _dismissMention() {
    _mentionOverlay?.remove();
    _mentionOverlay = null;
    _mentionStartOffset = -1;
    _mentionQuery = '';
  }

  /// Handle `notex://` link taps — navigate to the linked note.
  void _handleLinkTap(String url) {
    if (url.startsWith('notex://')) {
      final noteId = url.substring('notex://'.length);
      final note = widget.appState.notes.cast<Note?>().firstWhere(
            (n) => n?.id == noteId,
            orElse: () => null,
          );
      if (note != null) {
        widget.appState.selectNote(note);
      }
    }
    // Normal URLs are handled by Quill's default launcher
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = widget.themeState.accentColor;
    final currentNote = widget.appState.currentNote;
    // In tiling mode, toolbar reflects the focused note
    final note = _tiling.isActive
        ? _tiling.tiledNotes.cast<Note?>().firstWhere(
              (n) => n!.id == _tiling.focusedNoteId,
              orElse: () => _tiling.tiledNotes.isNotEmpty ? _tiling.tiledNotes.first : currentNote,
            )
        : currentNote;

    // In tiling mode, toolbar always uses default theme colors
    // (each panel handles its own note color independently)
    final noteColor = _tiling.isActive ? null : _parseNoteColor(note?.color);
    final hasNoteColor = noteColor != null;
    final editorBg = noteColor ?? widget.themeState.editorBgColor;
    // Lower opacity when note has a color so the glass effect shows through
    final bgAlpha = hasNoteColor ? 0.90 : 0.90;
    final chipBg = editorBg.withValues(alpha: hasNoteColor ? 0.90 : 0.90);
    final chipBorder = hasNoteColor
        ? Colors.white.withValues(alpha: 0.15)
        : widget.themeState.editorBorderColor;
    final chipText = hasNoteColor
        ? (editorBg.computeLuminance() > 0.5
              ? Colors.black87
              : Colors.white.withValues(alpha: 0.85))
        : widget.themeState.editorTextColor.withValues(alpha: 0.70);
    // Icons in toolbar chips: when a note color is set, pick white or black
    // for contrast instead of accent (which may blend with the bg).
    final iconColor = hasNoteColor
        ? (editorBg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white)
        : accentColor;

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

    final isCompact = widget.appState.isCompactMode;
    final isZen = widget.isZenMode;

    return Padding(
      padding: isZen
          ? const EdgeInsets.all(24)
          : isCompact
              ? const EdgeInsets.fromLTRB(4, 0, 4, 4)
              : const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // ── Static toolbar (top) — or Exit Zen button in zen mode ───
          if (!isZen)
            _buildEditorToolbar(note, accentColor, editorBg, chipBg, chipBorder, chipText, iconColor, isDark, isCompact, hasNoteColor),

          // Main editor area
          Expanded(
            child: note.isLocked && !GetIt.instance<SecurityState>().isNoteUnlocked(note.id)
                ? _buildLockedOverlay(context, editorBg, chipBorder, accentColor, note.id)
                : _tiling.isActive
                ? // Tiling mode: full tiling layout replaces the editor
                  TilingLayoutWidget(
                    tiling: _tiling,
                    appState: widget.appState,
                    themeState: widget.themeState,
                    accentColor: accentColor,
                    onChanged: () async {
                      if (!_tiling.isActive) {
                        // Tiling auto-exited — flush saves then refresh
                        await _tiling.flushAll();
                        await widget.appState.refreshNotes();
                        if (mounted) {
                          _loadNote(force: true);
                          setState(() {});
                        }
                      } else {
                        setState(() {});
                      }
                    },
                  )
                : Stack(
              children: [
                Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      // Quill toolbar — compact mode shows only essentials.
                      Container(
                        decoration: BoxDecoration(
                          color: editorBg.withValues(
                            alpha: hasNoteColor ? 0.90 : 0.92,
                          ),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.zero,
                            bottomRight: Radius.zero,
                          ),
                          border: Border.all(color: chipBorder, width: 1),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 4 : 8,
                          vertical: isCompact ? 2 : 4,
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
                                    showAlignmentButtons: !isCompact,
                                    showBackgroundColorButton: false,
                                    showClearFormat: false,
                                    showFontFamily: false,
                                    showFontSize: false,
                                    showInlineCode: !isCompact,
                                    showCodeBlock: !isCompact,
                                    showListCheck: true,
                                    showQuote: !isCompact,
                                    showLink: !isCompact,
                                    showStrikeThrough: !isCompact,
                                    showSearchButton: !isCompact,
                                    showSubscript: !isCompact,
                                    showSuperscript: !isCompact,
                                    showColorButton: !isCompact,
                                    showSmallButton: !isCompact,
                                    multiRowsDisplay: false,
                                    decoration: const BoxDecoration(),
                                    buttonOptions:
                                        QuillSimpleToolbarButtonOptions(
                                          base: QuillToolbarBaseButtonOptions(
                                            iconTheme: QuillIconTheme(
                                              iconButtonSelectedData:
                                                  IconButtonData(
                                                    color: hasNoteColor
                                                        ? iconColor
                                                        : accentColor,
                                                  ),
                                              iconButtonUnselectedData:
                                                  IconButtonData(
                                                    color: hasNoteColor
                                                        ? iconColor.withValues(
                                                            alpha: 0.60,
                                                          )
                                                        : widget
                                                              .themeState
                                                              .editorTextColor
                                                              .withValues(
                                                                alpha: 0.70,
                                                              ),
                                                  ),
                                            ),
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                              if (!isCompact) ...[
                                EditorTextControls(
                                  themeState: widget.themeState,
                                  noteColor: noteColor,
                                ),
                                const SizedBox(width: 4),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Editor content
                      // Listener ensures keyboard focus transfers on any
                      // pointer interaction so Ctrl+C / Ctrl+V works on the
                      // first try (desktop platforms may lose editor focus
                      // after toolbar clicks or other UI interactions).
                      Expanded(
                        child: Listener(
                          onPointerDown: (_) {
                            if (!_editorFocusNode.hasFocus) {
                              _editorFocusNode.requestFocus();
                            }
                          },
                          child: Container(
                          decoration: BoxDecoration(
                            color: editorBg.withValues(alpha: bgAlpha),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(20),
                              bottomRight: Radius.circular(20),
                            ),
                            border: Border(
                              left: BorderSide(color: chipBorder, width: 1),
                              right: BorderSide(color: chipBorder, width: 1),
                              bottom: BorderSide(color: chipBorder, width: 1),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.25 : 0.05,
                                ),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: EdgeInsets.all(isZen ? 32 : (isCompact ? 8 : 24)),
                          child: Focus(
                            onKeyEvent: (node, event) {
                              // Let mention overlay handle keys first
                              if (_mentionOverlay != null) {
                                final mentionState = _mentionKey.currentState
                                    as MentionOverlayState?;
                                if (mentionState != null &&
                                    mentionState.handleKey(event)) {
                                  return KeyEventResult.handled;
                                }
                              }

                              if (event is! KeyDownEvent &&
                                  event is! KeyRepeatEvent) {
                                return KeyEventResult.ignored;
                              }
                              if (event.logicalKey !=
                                  LogicalKeyboardKey.backspace) {
                                return KeyEventResult.ignored;
                              }
                              final ctrl = _quillController;
                              final sel = ctrl.selection;
                              if (!sel.isCollapsed) {
                                return KeyEventResult.ignored;
                              }
                              final offset = sel.baseOffset;
                              final style = ctrl.getSelectionStyle();
                              final indentAttr =
                                  style.attributes[Attribute.indent.key];
                              if (indentAttr == null) {
                                return KeyEventResult.ignored;
                              }
                              // Find start of current line
                              final text = ctrl.document.toPlainText();
                              int lineStart = offset;
                              while (lineStart > 0 &&
                                  text[lineStart - 1] != '\n') {
                                lineStart--;
                              }
                              if (offset != lineStart) {
                                return KeyEventResult.ignored;
                              }
                              // Cursor at start of indented line → decrease indent
                              final currentLevel = indentAttr.value as int;
                              if (currentLevel <= 1) {
                                ctrl.formatSelection(
                                    Attribute.clone(Attribute.indentL1, null));
                              } else {
                                ctrl.formatSelection(
                                    Attribute.getIndentLevel(currentLevel - 1));
                              }
                              return KeyEventResult.handled;
                            },
                            child: QuillEditor.basic(
                              controller: _quillController,
                              focusNode: _editorFocusNode,
                              config: QuillEditorConfig(
                                placeholder: 'Start writing your thoughts...',
                                padding: EdgeInsets.all(isCompact ? 4 : 8),
                                expands: true,
                                enableAlwaysIndentOnTab: true,
                                textSelectionThemeData: TextSelectionThemeData(
                                  cursorColor: accentColor,
                                ),
                                customStyles: _buildQuillStyles(
                                  isDark,
                                  noteColor: noteColor,
                                ),
                                customLinkPrefixes: const ['notex://'],
                                onLaunchUrl: (url) {
                                  if (url.startsWith('notex://')) {
                                    _handleLinkTap(url);
                                    return;
                                  }
                                  launchUrl(Uri.parse(url));
                                },
                                linkActionPickerDelegate: (context, link, node) async {
                                  if (link.startsWith('notex://')) {
                                    _handleLinkTap(link);
                                    return LinkMenuAction.none;
                                  }
                                  return defaultLinkActionPickerDelegate(context, link, node);
                                },
                              ),
                            ),
                          ),
                        ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

              ],
            ),
          ),
        ],
      ),
    );
  }


  // ── Tiling note picker ─────────────────────────────────────────────

  void _showTilingNotePicker(BuildContext context, Color accentColor) {
    final tiledIds = _tiling.tiledNotes.map((n) => n.id).toSet();
    final available = widget.appState.notes
        .where((n) => !tiledIds.contains(n.id))
        .toList();

    showDialog<Note>(
      context: context,
      builder: (dialogCtx) {
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
        final chipText = isDark ? Colors.white70 : Colors.grey.shade600;

        return SimpleDialog(
          title: const Text('Add note to tiling',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          children: [
            // Create new note option
            ListTile(
              leading: Icon(Icons.add_rounded, color: accentColor),
              title: Text('Create new note',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: accentColor)),
              onTap: () async {
                final newNote = await widget.appState.createNewNote();
                if (dialogCtx.mounted) {
                  Navigator.of(dialogCtx).pop(newNote);
                }
              },
            ),
            const Divider(height: 1),
            if (available.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No existing notes available',
                    style: TextStyle(fontSize: 13, color: chipText),
                    textAlign: TextAlign.center),
              )
            else
              SizedBox(
                width: 340,
                height: 300,
                child: ListView.builder(
                  itemCount: available.length,
                  itemBuilder: (ctx, i) {
                    final note = available[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        note.title.isEmpty ? 'Untitled' : note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      onTap: () => Navigator.of(dialogCtx).pop(note),
                    );
                  },
                ),
              ),
          ],
        );
      },
    ).then((selectedNote) {
      if (selectedNote != null) {
        setState(() => _tiling.addNote(selectedNote));
      }
    });
  }

  // ── Editor toolbar (static, top) ──────────────────────────────────────

  Widget _buildEditorToolbar(
    Note note, Color accentColor, Color editorBg, Color chipBg,
    Color chipBorder, Color chipText, Color iconColor, bool isDark,
    bool isCompact, bool hasNoteColor,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 560;
          final btnSize = isMobile ? 36.0 : 38.0;
          final btnRadius = isMobile ? 10.0 : 12.0;
          final btnIconSize = 16.0;

          return Row(
            children: [
              // Title
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _titleController,
                    onChanged: (_) {
                      _prevTitle = _titleController.text;
                      _onUserEdit();
                    },
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: hasNoteColor
                          ? iconColor
                          : widget.themeState.editorTextColor,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Note title...',
                      filled: true,
                      fillColor: chipBg,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(btnRadius),
                        borderSide: BorderSide(color: chipBorder, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(btnRadius),
                        borderSide: BorderSide(
                          color: accentColor.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8,
                      ),
                      prefixIcon: Icon(
                        Icons.edit_note_rounded,
                        color: iconColor.withValues(alpha: 0.6),
                        size: 18,
                      ),
                      hintStyle: TextStyle(
                        color: widget.themeState.editorMutedTextColor,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Date
              Text(
                '${note.updatedAt.month}/${note.updatedAt.day}/${note.updatedAt.year}',
                style: TextStyle(fontSize: 12, color: chipText),
              ),
              const SizedBox(width: 8),
              // Sync
              Icon(_getSyncIcon(note.syncStatus.name), size: 14, color: iconColor),
              const SizedBox(width: 6),
              // Color
              _buildColorButton(
                note, accentColor, iconColor, chipBg, chipBorder,
                size: btnSize, radius: btnRadius,
              ),
              const SizedBox(width: 4),
              // Share
              _buildToolbarBtn(
                icon: Icons.share_outlined, tooltip: 'Share note',
                onTap: () async {
                  final url = await widget.appState.shareNote(note);
                  if (url != null && context.mounted) {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: const Text('Share link copied!')),
                      );
                    }
                  }
                },
                size: btnSize, radius: btnRadius, iconSize: btnIconSize,
                iconColor: iconColor, chipBg: chipBg, chipBorder: chipBorder,
              ),
              const SizedBox(width: 4),
              // Ephemeral
              _buildToolbarBtn(
                icon: note.isEphemeral ? Icons.bolt_rounded : Icons.bolt_outlined,
                tooltip: note.isEphemeral ? 'Quick Note (24h)' : 'Make Quick Note',
                onTap: () => widget.appState.toggleEphemeral(note.id),
                size: btnSize, radius: btnRadius, iconSize: btnIconSize,
                iconColor: note.isEphemeral ? Colors.amber.shade600 : iconColor,
                chipBg: note.isEphemeral ? Colors.amber.withValues(alpha: 0.15) : chipBg,
                chipBorder: note.isEphemeral ? Colors.amber.withValues(alpha: 0.4) : chipBorder,
              ),
              const SizedBox(width: 4),
              // Lock
              _buildToolbarBtn(
                icon: note.isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                tooltip: note.isLocked ? 'Unlock' : 'Lock',
                onTap: () {
                  final sec = GetIt.instance<SecurityState>();
                  if (!note.isLocked && !sec.hasPin) {
                    _showSetPinDialog(context, sec, note);
                  } else {
                    widget.appState.toggleLock(note.id);
                  }
                },
                size: btnSize, radius: btnRadius, iconSize: btnIconSize,
                iconColor: note.isLocked ? Colors.red.shade400 : iconColor,
                chipBg: note.isLocked ? Colors.red.withValues(alpha: 0.15) : chipBg,
                chipBorder: note.isLocked ? Colors.red.withValues(alpha: 0.4) : chipBorder,
              ),
              const SizedBox(width: 4),
              // Tiling
              _buildToolbarBtn(
                icon: Icons.dashboard_rounded,
                tooltip: _tiling.isActive
                    ? 'Tiling (${_tiling.tileCount}/${TilingState.maxTiles})'
                    : 'Tiling View',
                onTap: () async {
                  if (!_tiling.isActive) {
                    // Save current editor content before entering tiling
                    await widget.appState.autoSaveService.forceSave(
                      noteId: note.id,
                      title: _titleController.text,
                      content: _serializeContent(),
                    );
                    await widget.appState.refreshNotes();
                    if (!mounted) return;
                    // Use the fresh note from DB
                    final freshNote = widget.appState.currentNote ?? note;
                    setState(() => _tiling.enterTiling(initialNotes: [freshNote]));
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _showTilingNotePicker(context, accentColor);
                    });
                  }
                },
                size: btnSize, radius: btnRadius, iconSize: btnIconSize,
                iconColor: _tiling.isActive ? accentColor : iconColor,
                chipBg: _tiling.isActive ? accentColor.withValues(alpha: 0.15) : chipBg,
                chipBorder: _tiling.isActive ? accentColor.withValues(alpha: 0.4) : chipBorder,
              ),
              if (_tiling.isActive && _tiling.canAddTile) ...[
                const SizedBox(width: 4),
                _buildToolbarBtn(
                  icon: Icons.add_rounded, tooltip: 'Add note',
                  onTap: () => _showTilingNotePicker(context, accentColor),
                  size: btnSize, radius: btnRadius, iconSize: btnIconSize,
                  iconColor: iconColor, chipBg: chipBg, chipBorder: chipBorder,
                ),
              ],
              if (_tiling.isActive) ...[
                const SizedBox(width: 4),
                _buildToolbarBtn(
                  icon: Icons.close_fullscreen_rounded, tooltip: 'Exit Tiling',
                  onTap: () async {
                    // Flush all panel edits BEFORE destroying them
                    await _tiling.flushAll();
                    _tiling.exitTiling();
                    // Small delay for any fire-and-forget dispose saves
                    await Future.delayed(const Duration(milliseconds: 100));
                    await widget.appState.refreshNotes();
                    if (mounted) {
                      _loadNote(force: true);
                      setState(() {});
                    }
                  },
                  size: btnSize, radius: btnRadius, iconSize: btnIconSize,
                  iconColor: iconColor, chipBg: chipBg, chipBorder: chipBorder,
                ),
              ],
              const SizedBox(width: 4),
              // Zen
              _buildToolbarBtn(
                icon: Icons.spa_outlined, tooltip: 'Focus Mode',
                onTap: () => widget.appState.enterZenMode(),
                size: btnSize, radius: btnRadius, iconSize: btnIconSize,
                iconColor: iconColor, chipBg: chipBg, chipBorder: chipBorder,
              ),
              // Compact (disabled in tiling mode)
              if (!_tiling.isActive) ...[
                const SizedBox(width: 4),
                _buildToolbarBtn(
                  icon: isCompact ? Icons.fullscreen_rounded : Icons.picture_in_picture_alt_outlined,
                  tooltip: isCompact ? 'Full size' : 'Compact',
                  onTap: () => isCompact
                      ? widget.appState.exitCompactMode()
                      : widget.appState.enterCompactMode(note),
                  size: btnSize, radius: btnRadius, iconSize: btnIconSize,
                  iconColor: iconColor, chipBg: chipBg, chipBorder: chipBorder,
                ),
              ],
              // Save indicator
              ValueListenableBuilder<String>(
                valueListenable: _saveStatus,
                builder: (context, status, _) {
                  if (status != 'saved') return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.check_circle_outline_rounded,
                        size: 14,
                        color: isDark
                            ? Colors.green.shade300
                            : Colors.green.shade600),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Toolbar button helper ────────────────────────────────────────────

  Widget _buildToolbarBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required double size,
    required double radius,
    required double iconSize,
    required Color iconColor,
    required Color chipBg,
    required Color chipBorder,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          height: size,
          width: size,
          decoration: BoxDecoration(
            color: chipBg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: chipBorder, width: 1),
          ),
          child: Icon(icon, size: iconSize, color: iconColor),
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  DefaultStyles _buildQuillStyles(bool isDark, {Color? noteColor}) {
    final fontSize = widget.themeState.editorFontSize;
    final lh = widget.themeState.editorLineHeight;

    // When a note color is set, adapt text color for contrast.
    final textColor = noteColor != null
        ? (noteColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white)
        : widget.themeState.editorTextColor;
    final mutedColor = noteColor != null
        ? textColor.withValues(alpha: 0.5)
        : widget.themeState.editorMutedTextColor;

    return DefaultStyles(
      placeHolder: DefaultTextBlockStyle(
        TextStyle(fontSize: fontSize, height: lh, color: mutedColor),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(6, 6),
        const VerticalSpacing(0, 0),
        null,
      ),
      paragraph: DefaultTextBlockStyle(
        TextStyle(fontSize: fontSize, height: lh, color: textColor),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(6, 6),
        const VerticalSpacing(0, 0),
        null,
      ),
      lists: DefaultListBlockStyle(
        TextStyle(fontSize: fontSize, height: lh, color: textColor),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(6, 6),
        const VerticalSpacing(0, 0),
        null,
        null,
      ),
      leading: DefaultTextBlockStyle(
        TextStyle(fontSize: fontSize, height: lh, color: textColor),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(0, 0),
        const VerticalSpacing(0, 0),
        null,
      ),
      link: TextStyle(
        color: widget.themeState.accentColor,
        decoration: TextDecoration.underline,
        decorationColor: widget.themeState.accentColor.withValues(alpha: 0.4),
        decorationStyle: TextDecorationStyle.solid,
      ),
    );
  }

  // Reusable controllers for the locked overlay to avoid leaks.
  final _lockPinController = TextEditingController();
  final _lockErrorNotifier = ValueNotifier<String?>(null);

  Widget _buildLockedOverlay(
    BuildContext context,
    Color editorBg,
    Color chipBorder,
    Color accentColor,
    String noteId,
  ) {
    _lockPinController.clear();
    _lockErrorNotifier.value = null;
    final securityState = GetIt.instance<SecurityState>();

    return Container(
      decoration: BoxDecoration(
        color: editorBg.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: chipBorder, width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'This note is locked',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your PIN to view this note',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade500,
                  ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              child: TextField(
                controller: _lockPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'Enter PIN',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onSubmitted: (value) {
                  if (securityState.verifyAndUnlock(noteId, value)) {
                    setState(() {});
                  } else {
                    _lockErrorNotifier.value = 'Incorrect PIN';
                  }
                },
              ),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: _lockErrorNotifier,
              builder: (_, error, __) => error != null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12)),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                if (securityState.verifyAndUnlock(noteId, _lockPinController.text)) {
                  setState(() {});
                } else {
                  _lockErrorNotifier.value = 'Incorrect PIN';
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Unlock'),
            ),
          ],
        ),
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

  // ── Note color picker ─────────────────────────────────────────────────────

  Widget _buildColorButton(
    Note note,
    Color accentColor,
    Color iconColor,
    Color chipBg,
    Color chipBorder, {
    double size = 44,
    double radius = 14,
  }) {
    final noteColor = _parseNoteColor(note.color);
    return InkWell(
      onTap: () => _showNoteColorPicker(note, accentColor),
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: chipBorder, width: 1),
        ),
        child: noteColor != null
            ? Center(
                child: Container(
                  width: size * 0.45,
                  height: size * 0.45,
                  decoration: BoxDecoration(
                    color: noteColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: iconColor.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                ),
              )
            : Icon(Icons.palette_outlined,
                size: size * 0.41, color: iconColor),
      ),
    );
  }

  Color? _parseNoteColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final value = int.tryParse(hex, radix: 16);
    return value != null ? Color(value) : null;
  }

  void _showNoteColorPicker(Note note, Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final currentColor = _parseNoteColor(note.color);

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Note Color',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 20),
                // Clear color option + preset swatches
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Clear / no color
                    _buildColorSwatch(
                      ctx,
                      note: note,
                      color: null,
                      isSelected: currentColor == null,
                      accentColor: accentColor,
                      isDark: isDark,
                      icon: Icons.block_rounded,
                    ),
                    // Presets
                    ...ThemeState.presetColors.map(
                      (c) => _buildColorSwatch(
                        ctx,
                        note: note,
                        color: c,
                        isSelected: currentColor?.value == c.value,
                        accentColor: accentColor,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Custom color picker button
                _buildCustomNoteColorSwatch(
                  ctx,
                  note: note,
                  currentColor: currentColor ?? accentColor,
                  accentColor: accentColor,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildColorSwatch(
    BuildContext ctx, {
    required Note note,
    required Color? color,
    required bool isSelected,
    required Color accentColor,
    required bool isDark,
    IconData? icon,
  }) {
    return InkWell(
      onTap: () {
        final hex = color != null
            ? color.value.toRadixString(16).padLeft(8, '0').toUpperCase()
            : null;
        widget.appState.updateNoteColor(note, hex);
        Navigator.of(ctx).pop();
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              color ?? (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
          border: isSelected
              ? Border.all(
                  color: isDark ? Colors.white : Colors.black87,
                  width: 3,
                )
              : Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.20)
                      : Colors.grey.shade400,
                  width: 1,
                ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.5),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: icon != null
            ? Icon(
                icon,
                size: 16,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              )
            : isSelected
            ? Icon(
                Icons.check,
                size: 16,
                color: (color?.computeLuminance() ?? 0) > 0.5
                    ? Colors.black87
                    : Colors.white,
              )
            : null,
      ),
    );
  }

  Widget _buildCustomNoteColorSwatch(
    BuildContext ctx, {
    required Note note,
    required Color currentColor,
    required Color accentColor,
    required bool isDark,
  }) {
    final isCustom = !ThemeState.presetColors.any(
      (c) => c.value == currentColor.value,
    );
    return InkWell(
      onTap: () async {
        Navigator.of(ctx).pop();
        final result = await _showCustomNoteColorPicker(
          currentColor,
          accentColor,
          isDark,
        );
        if (result != null) {
          final hex = result.value
              .toRadixString(16)
              .padLeft(8, '0')
              .toUpperCase();
          widget.appState.updateNoteColor(note, hex);
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isCustom
              ? null
              : const SweepGradient(
                  colors: [
                    Color(0xFFFF0000),
                    Color(0xFFFFFF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FFFF),
                    Color(0xFF0000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0000),
                  ],
                ),
          color: isCustom ? currentColor : null,
          border: isCustom
              ? Border.all(
                  color: isDark ? Colors.white : Colors.black87,
                  width: 3,
                )
              : Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.20)
                      : Colors.grey.shade400,
                  width: 1.5,
                ),
        ),
        child: isCustom
            ? Icon(
                Icons.check,
                size: 16,
                color: currentColor.computeLuminance() > 0.5
                    ? Colors.black87
                    : Colors.white,
              )
            : null,
      ),
    );
  }

  Future<Color?> _showCustomNoteColorPicker(
    Color initialColor,
    Color accentColor,
    bool isDark,
  ) async {
    Color picked = initialColor;
    final bg = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    return showDialog<Color>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: bg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Custom Color',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ColorPicker(
                      pickerColor: picked,
                      onColorChanged: (c) => setDialogState(() => picked = c),
                      colorPickerWidth: 300,
                      pickerAreaHeightPercent: 0.7,
                      enableAlpha: false,
                      displayThumbColor: true,
                      hexInputBar: true,
                      labelTypes: const [],
                      pickerAreaBorderRadius: const BorderRadius.all(
                        Radius.circular(12),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(null),
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: accentColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(picked),
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── PIN dialogs ──────────────────────────────────────────────────────────

  void _showSetPinDialog(
    BuildContext context,
    SecurityState securityState,
    Note note,
  ) {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    final errorNotifier = ValueNotifier<String?>(null);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Set a PIN to lock notes. You\'ll need this PIN to view locked notes.'),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'PIN',
                hintText: 'Enter 4-6 digit PIN',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Confirm PIN',
                hintText: 'Re-enter PIN',
              ),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: errorNotifier,
              builder: (_, error, __) => error != null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12)),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final pin = pinController.text;
              final confirm = confirmController.text;
              if (pin.length < 4 || pin.length > 6) {
                errorNotifier.value = 'PIN must be 4-6 digits';
                return;
              }
              if (pin != confirm) {
                errorNotifier.value = 'PINs do not match';
                return;
              }
              await securityState.setPin(pin);
              widget.appState.toggleLock(note.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Set PIN & Lock'),
          ),
        ],
      ),
    );
  }
}

