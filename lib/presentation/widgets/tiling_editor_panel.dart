import 'dart:async';
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:get_it/get_it.dart';
import '../../application/use_cases/update_note_use_case.dart';
import '../../domain/entities/note.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../state/tiling_state.dart';

/// A self-contained editor panel for one note inside the tiling layout.
///
/// Each panel manages its own [QuillController], auto-save polling, and
/// title editing — identical to the former `_SplitEditorPanel`.
class TilingEditorPanel extends StatefulWidget {
  final Note note;
  final AppState appState;
  final ThemeState themeState;
  final Color accentColor;
  final TilingState tiling;
  final VoidCallback onClose;

  const TilingEditorPanel({
    super.key,
    required this.note,
    required this.appState,
    required this.themeState,
    required this.accentColor,
    required this.tiling,
    required this.onClose,
  });

  @override
  State<TilingEditorPanel> createState() => _TilingEditorPanelState();
}

class _TilingEditorPanelState extends State<TilingEditorPanel> {
  QuillController? _quillController;
  TextEditingController? _titleController;
  String? _loadedNoteId;
  Timer? _debounce;
  Timer? _hideTimer;
  bool _isDirty = false;
  final ValueNotifier<String> _saveStatus = ValueNotifier('');

  static final _controllerConfig = QuillControllerConfig(
    clipboardConfig: QuillClipboardConfig(
      enableExternalRichPaste: false,
    ),
  );

  @override
  void initState() {
    super.initState();
    _loadNote(widget.note);
  }

  @override
  void didUpdateWidget(covariant TilingEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.note.id != _loadedNoteId) {
      _loadNote(widget.note);
    } else if (!_isDirty && widget.note.content != oldWidget.note.content) {
      // Same note but content updated externally (e.g. edited in notes list)
      _loadNote(widget.note, force: true);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hideTimer?.cancel();
    // Don't unregister saver here — flushAll needs it to still work
    // if dispose races with flush. Save one last time if dirty.
    if (_isDirty && _loadedNoteId != null && _quillController != null) {
      GetIt.instance<UpdateNoteUseCase>().execute(
        noteId: _loadedNoteId!,
        title: _titleController!.text,
        content: _serializeContent(),
      );
    }
    _quillController?.dispose();
    _titleController?.dispose();
    _saveStatus.dispose();
    super.dispose();
  }

  void _loadNote(Note note, {bool force = false}) {
    if (!force && note.id == _loadedNoteId) return;
    if (_isDirty) _awaitableSave();

    _debounce?.cancel();
    _quillController?.dispose();
    _titleController?.dispose();

    _loadedNoteId = note.id;
    _titleController = TextEditingController(text: note.title);
    _titleController!.addListener(_onEdit);

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

    _isDirty = false;
    // Listen for content changes (event-driven, no polling)
    _quillController!.document.changes.listen((_) => _onEdit());

    // Register saver so TilingState.flushAll() can save this panel
    widget.tiling.registerSaver(note.id, _awaitableSave);
  }

  void _onEdit() {
    if (_loadedNoteId == null) return;
    _isDirty = true;
    if (mounted) _saveStatus.value = '';
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _forceSave);
  }

  String _serializeContent() =>
      jsonEncode(_quillController!.document.toDelta().toJson());

  /// Always saves current content to DB. Used by flushAll before exit.
  Future<void> _awaitableSave() async {
    if (_loadedNoteId == null || _quillController == null) return;
    _debounce?.cancel();
    _isDirty = false;
    final title = _titleController!.text;
    final content = _serializeContent();
    await GetIt.instance<UpdateNoteUseCase>().execute(
      noteId: _loadedNoteId!,
      title: title,
      content: content,
    );
    if (!mounted) return;
    _saveStatus.value = 'saved';
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _saveStatus.value = '';
    });
  }

  /// Debounce callback — only saves if dirty.
  void _forceSave() {
    if (!_isDirty) return;
    _awaitableSave();
  }

  void _claimFocus() {
    if (widget.tiling.focusedNoteId != widget.note.id) {
      // Defer so we don't interfere with QuillEditor's pointer handling
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.tiling.focusedNoteId = widget.note.id;
      });
    }
  }

  Color? _parseNoteColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      final cleaned = hex.replaceFirst('#', '');
      if (cleaned.length == 6) return Color(int.parse('FF$cleaned', radix: 16));
      if (cleaned.length == 8) return Color(int.parse(cleaned, radix: 16));
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final noteColor = _parseNoteColor(widget.note.color);
    final hasNoteColor = noteColor != null;
    final editorBg = noteColor ?? widget.themeState.editorBgColor;
    final chipBorder = hasNoteColor
        ? Colors.white.withValues(alpha: 0.15)
        : widget.themeState.editorBorderColor;
    final chipText = hasNoteColor
        ? (editorBg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white70)
        : (isDark ? Colors.white70 : Colors.grey.shade600);
    final textColor = hasNoteColor
        ? (editorBg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white)
        : (isDark ? Colors.white : Colors.black87);

    if (_quillController == null) return const SizedBox.shrink();

    return Listener(
      onPointerDown: (e) {
        // Only claim focus on primary button (left click), not right-click
        if (e.buttons == kPrimaryButton) _claimFocus();
      },
      child: _FocusBorder(
        key: ValueKey('border_${widget.note.id}'),
        tiling: widget.tiling,
        noteId: widget.note.id,
        accentColor: widget.accentColor,
        defaultBorder: chipBorder,
        child: Container(
          decoration: BoxDecoration(
            color: editorBg.withValues(alpha: isDark ? 0.90 : 0.92),
            borderRadius: BorderRadius.circular(16),
          ),
      child: Column(
          children: [
            // Toolbar row: quill toolbar + save indicator + close
            Container(
              decoration: BoxDecoration(
                color: editorBg.withValues(alpha: isDark ? 0.90 : 0.92),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                border: Border(
                    bottom: BorderSide(color: chipBorder, width: 1)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Focus(
                      canRequestFocus: false,
                      descendantsAreFocusable: false,
                      child: QuillSimpleToolbar(
                        controller: _quillController!,
                        config: QuillSimpleToolbarConfig(
                    showAlignmentButtons: false,
                    showBackgroundColorButton: false,
                    showClearFormat: false,
                    showFontFamily: false,
                    showFontSize: false,
                    showSearchButton: false,
                    showInlineCode: false,
                    showCodeBlock: false,
                    showLink: false,
                    showClipboardCut: false,
                    showClipboardCopy: false,
                    showClipboardPaste: false,
                    showQuote: false,
                    showStrikeThrough: false,
                    showSubscript: false,
                    showSuperscript: false,
                    showColorButton: false,
                    showSmallButton: false,
                    multiRowsDisplay: false,
                    decoration: const BoxDecoration(),
                  ),
                ),
              ),
                  ),
                  // Save indicator
                  ValueListenableBuilder<String>(
                    valueListenable: _saveStatus,
                    builder: (context, status, _) {
                      if (status == 'saved') {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.check_circle_outline_rounded,
                              size: 12,
                              color: isDark
                                  ? Colors.green.shade300
                                  : Colors.green.shade600),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  // Close button
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      onPressed: () {
                        _forceSave();
                        widget.onClose();
                      },
                      icon: Icon(Icons.close_rounded,
                          size: 12, color: chipText),
                      padding: EdgeInsets.zero,
                      splashRadius: 10,
                      tooltip: 'Close panel',
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            // Editor
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: QuillEditor.basic(
                  controller: _quillController!,
                  config: QuillEditorConfig(
                    placeholder: 'Start writing...',
                    padding: const EdgeInsets.all(6),
                    expands: true,
                    textSelectionThemeData: TextSelectionThemeData(
                      cursorColor: widget.accentColor,
                    ),
                    customStyles: DefaultStyles(
                      paragraph: DefaultTextBlockStyle(
                        TextStyle(
                          fontSize: widget.themeState.editorFontSize,
                          height: widget.themeState.editorLineHeight,
                          color: textColor,
                        ),
                        const HorizontalSpacing(0, 0),
                        const VerticalSpacing(4, 4),
                        const VerticalSpacing(0, 0),
                        null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// Draws a focus border using TilingState.focusNotifier for instant updates.
class _FocusBorder extends StatelessWidget {
  final TilingState tiling;
  final String noteId;
  final Color accentColor;
  final Color defaultBorder;
  final Widget child;

  const _FocusBorder({
    super.key,
    required this.tiling,
    required this.noteId,
    required this.accentColor,
    required this.defaultBorder,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: tiling.focusNotifier,
      builder: (context, focusedId, _) {
        final isFocused = focusedId == noteId;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isFocused
                  ? accentColor.withValues(alpha: 0.6)
                  : defaultBorder,
              width: isFocused ? 2 : 1,
            ),
          ),
          child: child,
        );
      },
    );
  }
}
