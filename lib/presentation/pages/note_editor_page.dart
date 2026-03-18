import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../../domain/entities/note.dart';
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

    final noteColor = _parseNoteColor(note?.color);
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

    return Padding(
      padding: isCompact
          ? const EdgeInsets.fromLTRB(4, 0, 4, 4)
          : const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // Top controls row: title + toolbar
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 560;

              // ── Shared widgets ──

              final titleField = SizedBox(
                height: isMobile ? 40 : 44,
                child: TextField(
                  controller: _titleController,
                  onChanged: (_) {
                    _prevTitle = _titleController.text;
                    _onUserEdit();
                  },
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: isMobile ? 14 : 15,
                    color: hasNoteColor
                        ? iconColor
                        : widget.themeState.editorTextColor,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Note title...',
                    filled: true,
                    fillColor: chipBg,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
                      borderSide: BorderSide(color: chipBorder, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
                      borderSide: BorderSide(
                        color: accentColor.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : 16,
                      vertical: isMobile ? 10 : 12,
                    ),
                    prefixIcon: Icon(
                      Icons.edit_note_rounded,
                      color: iconColor.withValues(alpha: 0.6),
                      size: isMobile ? 18 : 20,
                    ),
                    hintStyle: TextStyle(
                      color: widget.themeState.editorMutedTextColor,
                      fontWeight: FontWeight.w500,
                      fontSize: isMobile ? 14 : 15,
                    ),
                  ),
                ),
              );

              final dateChip = Container(
                height: isMobile ? 36 : 44,
                padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 10 : 14),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius:
                      BorderRadius.circular(isMobile ? 12 : 14),
                  border: Border.all(color: chipBorder, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: isMobile ? 12 : 14,
                      color: iconColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isMobile
                          ? '${note.updatedAt.month}/${note.updatedAt.day}'
                          : '${note.updatedAt.month}/${note.updatedAt.day}/${note.updatedAt.year}',
                      style: TextStyle(
                        fontSize: isMobile ? 11 : 13,
                        fontWeight: FontWeight.w500,
                        color: chipText,
                      ),
                    ),
                  ],
                ),
              );

              final btnSize = isMobile ? 36.0 : 44.0;
              final btnRadius = isMobile ? 12.0 : 14.0;
              final btnIconSize = isMobile ? 16.0 : 18.0;

              final syncIndicator = Container(
                height: btnSize,
                width: btnSize,
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(btnRadius),
                  border: Border.all(color: chipBorder, width: 1),
                ),
                child: Icon(
                  _getSyncIcon(note.syncStatus.name),
                  size: btnIconSize,
                  color: iconColor,
                ),
              );

              final colorButton = _buildColorButton(
                note, accentColor, iconColor, chipBg, chipBorder,
                size: btnSize, radius: btnRadius,
              );

              final compactToggle = InkWell(
                onTap: () => isCompact
                    ? widget.appState.exitCompactMode()
                    : widget.appState.enterCompactMode(note),
                borderRadius: BorderRadius.circular(btnRadius),
                child: Container(
                  height: btnSize,
                  width: btnSize,
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(btnRadius),
                    border: Border.all(color: chipBorder, width: 1),
                  ),
                  child: Icon(
                    isCompact
                        ? Icons.fullscreen_rounded
                        : Icons.picture_in_picture_alt_outlined,
                    size: btnIconSize,
                    color: iconColor,
                  ),
                ),
              );

              final saveIndicator = ValueListenableBuilder<String>(
                valueListenable: _saveStatus,
                builder: (context, status, _) {
                  return AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    alignment: Alignment.centerLeft,
                    child: status == 'saved'
                        ? Container(
                            height: btnSize,
                            margin: EdgeInsets.only(
                                left: isMobile ? 6 : 8),
                            padding: EdgeInsets.symmetric(
                                horizontal: isMobile ? 8 : 12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : Colors.green.shade50,
                              borderRadius:
                                  BorderRadius.circular(btnRadius),
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
                                  size: isMobile ? 12 : 14,
                                  color: isDark
                                      ? Colors.green.shade300
                                      : Colors.green.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Saved',
                                  style: TextStyle(
                                    fontSize: isMobile ? 10 : 12,
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
              );

              if (isMobile) {
                // Mobile: single row — title + color + save only
                return Row(
                  children: [
                    Expanded(child: titleField),
                    const SizedBox(width: 8),
                    colorButton,
                    saveIndicator,
                  ],
                );
              }

              // Desktop: single row (original)
              return Row(
                children: [
                  Expanded(flex: 3, child: titleField),
                  const SizedBox(width: 12),
                  dateChip,
                  const SizedBox(width: 12),
                  syncIndicator,
                  const SizedBox(width: 8),
                  colorButton,
                  const SizedBox(width: 8),
                  compactToggle,
                  saveIndicator,
                ],
              );
            },
          ),

          const SizedBox(height: 12),

          // Main editor area
          Expanded(
            child: Row(
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
                      Expanded(
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
                          padding: EdgeInsets.all(isCompact ? 8 : 24),
                          child: QuillEditor.basic(
                            controller: _quillController,
                            focusNode: _editorFocusNode,
                            config: QuillEditorConfig(
                              placeholder: 'Start writing your thoughts...',
                              padding: EdgeInsets.all(isCompact ? 4 : 8),
                              expands: true,
                              textSelectionThemeData: TextSelectionThemeData(
                                cursorColor: accentColor,
                              ),
                              customStyles: _buildQuillStyles(
                                isDark,
                                noteColor: noteColor,
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
          ),
        ],
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
}
