import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../infrastructure/content/note_content_format.dart';
import 'markdown_code_block_builder.dart';

/// Which set of formatting controls the [NoteMarkdownEditor] exposes.
///
/// The three values map to the three editor surfaces in the app:
/// * [full] — the primary note editor (all controls).
/// * [minimal] — the tiling / split view (essential controls only).
/// * [none] — the notes list preview (no toolbar at all).
enum EditorToolbarProfile { full, minimal, none }

/// Which surface(s) the editor shows for a single note.
/// * [edit] — the source Markdown [TextField] only.
/// * [preview] — the rendered Markdown only.
/// * [split] — the field and the live preview side by side (editing the field
///   refreshes the preview as you type).
enum EditorViewMode { edit, preview, split }

/// Serialization helpers so hosts can persist and restore the view mode by name.
extension EditorViewModeName on EditorViewMode {
  /// Parses a persisted [EditorViewMode.name], falling back to [edit] for any
  /// unknown or corrupt value so a bad stored setting never crashes the editor.
  static EditorViewMode fromName(String? name) {
    for (final mode in EditorViewMode.values) {
      if (mode.name == name) return mode;
    }
    return EditorViewMode.edit;
  }
}

/// A reusable source-mode Markdown editor shared by every editor surface.
///
/// The user edits raw Markdown in a plain [TextField] and can flip to a
/// rendered preview (via `flutter_markdown_plus`) with an edit⇄preview toggle.
/// There is no WYSIWYG layer: the [TextEditingController]'s text IS the
/// Markdown document.
///
/// It accepts note content that may be either Markdown or legacy Quill Delta
/// JSON: [initialContent] is always normalized through
/// [NoteContentFormat.ensureMarkdown] on load, so legacy notes open as Markdown
/// text. Every real edit emits the current full Markdown string through
/// [onChanged].
///
/// The controller is seeded programmatically in `initState`, which does NOT
/// trigger [TextField.onChanged], so simply opening a note never fires
/// [onChanged] and never marks it dirty. Toolbar inserts mutate the controller
/// directly and therefore call [onChanged] explicitly.
///
/// Debouncing is intentionally NOT handled here — the surfaces that host this
/// widget already debounce writes.
class NoteMarkdownEditor extends StatefulWidget {
  const NoteMarkdownEditor({
    super.key,
    required this.initialContent,
    required this.onChanged,
    this.toolbar = EditorToolbarProfile.full,
    this.readOnly = false,
    this.initiallyPreview = false,
    this.initialViewMode,
    this.onViewModeChanged,
    this.autofocus = false,
    this.onInternalLink,
    this.onExternalLink,
    this.fontSize,
    this.lineHeight,
    this.textColor,
    this.trailing,
  });

  /// Raw stored note content. May be Markdown or legacy Quill Delta JSON; it is
  /// normalized to Markdown via [NoteContentFormat.ensureMarkdown] on load.
  final String initialContent;

  /// Called with the current full Markdown string on every real edit.
  ///
  /// Never fired during the initial programmatic seeding of the controller.
  final ValueChanged<String> onChanged;

  /// Which toolbar to render. Ignored (no toolbar) when [readOnly] is true or
  /// when set to [EditorToolbarProfile.none].
  final EditorToolbarProfile toolbar;

  /// When true, the widget renders the rendered preview only — no [TextField],
  /// no toolbar, and no edit⇄preview toggle.
  final bool readOnly;

  /// When true, the editor opens in the rendered preview instead of the edit
  /// [TextField] — but ONLY when [initialContent] normalizes to non-empty
  /// Markdown. An empty/new note always opens in the editor so the user can
  /// start typing immediately. Ignored when [readOnly] is true.
  final bool initiallyPreview;

  /// The view mode the editor should open in, taking precedence over
  /// [initiallyPreview]. Used to restore a persisted last-used surface (e.g.
  /// reopen in split). When null, [initiallyPreview] decides. A [preview]
  /// request on an empty note still falls back to edit so a new note is
  /// immediately typable.
  final EditorViewMode? initialViewMode;

  /// Called whenever the user switches the view mode via the toolbar toggles or
  /// the keyboard shortcut, with the new mode. Lets the host persist the
  /// last-used surface. Never fired for read-only surfaces (they have no
  /// toggles) nor during initial seeding.
  final ValueChanged<EditorViewMode>? onViewModeChanged;

  /// When true, this editor grabs focus and the global Cmd/Ctrl+E toggle slot
  /// as soon as it mounts, so the shortcut works immediately without a click —
  /// in any [initialViewMode], not just the auto-focused preview. Set this only
  /// for the primary editor surface: leaving it false keeps multiple mounted
  /// editors (tiling panels, the list preview) from fighting over focus.
  /// Ignored when [readOnly] is true.
  final bool autofocus;

  /// Called when the user taps a `notex://<id>` link in the preview, with the
  /// `<id>` portion. When null, internal-link taps are ignored.
  final void Function(String noteId)? onInternalLink;

  /// Called when the user taps any non-`notex://` link in the preview, with the
  /// full URL. When null, external-link taps are ignored. Note: this widget
  /// does NOT launch URLs itself — the hosting surface decides what to do.
  final void Function(String url)? onExternalLink;

  /// Optional font size applied to both the edit [TextField] and the preview
  /// body text. When null the theme default is used.
  final double? fontSize;

  /// Optional line height (as a multiple of the font size) applied to both the
  /// edit [TextField] and the preview body text. When null the theme default is
  /// used.
  final double? lineHeight;

  /// Optional text color applied to both the edit [TextField] and the preview
  /// body text. When null a theme-aware [ColorScheme.onSurface] is used so the
  /// content stays readable in light and dark mode.
  final Color? textColor;

  /// Optional widget rendered on the right side of the control bar, after the
  /// scrollable toolbar buttons and before the edit⇄preview toggle. It sits
  /// OUTSIDE the horizontal scroll area so it stays visible on narrow widths.
  /// When null the control bar layout is unchanged.
  final Widget? trailing;

  @override
  State<NoteMarkdownEditor> createState() => _NoteMarkdownEditorState();
}

class _NoteMarkdownEditorState extends State<NoteMarkdownEditor> {
  static const _internalScheme = 'notex';

  /// The editor instance that currently owns the global Cmd/Ctrl+E toggle.
  ///
  /// The toggle is delivered through a process-wide [HardwareKeyboard] handler
  /// so it fires no matter where focus is (a Focus-subtree handler stops working
  /// as soon as the user selects preview text or clicks away). When several
  /// editors are mounted at once (tiling panels) they all register a handler, so
  /// this static picks a single winner: only the instance identical to
  /// [_activeInstance] acts on the key. It is claimed on mount (when free) and
  /// re-claimed whenever an editor's field or preview takes focus, so the
  /// last-interacted editor wins. The app's AnimatedSwitcher keeps the note
  /// editor and notes list from being co-mounted, so the common case is a single
  /// editor that always owns the toggle.
  static _NoteMarkdownEditorState? _activeInstance;

  late final TextEditingController _controller;

  /// Focus node for the edit [TextField], so a Cmd/Ctrl+E toggle from preview
  /// back to edit can immediately return focus to the field for typing.
  final FocusNode _editFocusNode = FocusNode();

  /// Focus node for the preview subtree. It takes focus while the preview shows
  /// so this editor claims the active-toggle slot (see [_activeInstance]); the
  /// toggle itself is delivered globally, not through this node.
  final FocusNode _previewFocusNode = FocusNode();

  /// Which surface(s) this editor currently shows (edit / preview / split).
  EditorViewMode _viewMode = EditorViewMode.edit;

  /// The source field is visible in both edit and split modes.
  bool get _editVisible => _viewMode != EditorViewMode.preview;

  @override
  void initState() {
    super.initState();
    // Seed the controller programmatically. Setting the controller's text here
    // does NOT invoke TextField.onChanged, so opening a note never fires
    // widget.onChanged. Only real user typing (and explicit toolbar inserts)
    // do.
    final markdown = NoteContentFormat.ensureMarkdown(widget.initialContent);
    _controller = TextEditingController(text: markdown);
    _viewMode = _resolveInitialViewMode(markdown);
    // In split mode the preview reads _controller.text directly, but user typing
    // fires TextField.onChanged (the host callback) — not setState here. So the
    // preview would go stale. Listen to the controller and rebuild live, but
    // ONLY in split mode where both surfaces are on screen at once.
    _controller.addListener(_handleControllerChange);

    // Claim the active-toggle slot when nothing else holds it, so a single
    // mounted editor always receives Cmd/Ctrl+E. Read-only surfaces have no
    // toggle, so they never claim it.
    if (!widget.readOnly && _activeInstance == null) {
      _activeInstance = this;
    }
    // The primary editor takes over the toggle slot AND focus on mount, so the
    // shortcut works immediately without a click — even when it opens in edit
    // or split, which (unlike preview) do not auto-focus a surface. Force the
    // claim past any editor that already holds it (e.g. the list preview still
    // mounted behind this page).
    if (widget.autofocus && !widget.readOnly) {
      _activeInstance = this;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_viewMode == EditorViewMode.preview) {
          _previewFocusNode.requestFocus();
        } else {
          _editFocusNode.requestFocus();
        }
      });
    }
    // Re-claim the slot whenever this editor's field or preview gains focus, so
    // the last-interacted editor wins when several are mounted.
    _editFocusNode.addListener(_handleFocusChange);
    _previewFocusNode.addListener(_handleFocusChange);
    // A process-wide handler makes the toggle focus-independent: it still fires
    // after focus leaves the editor subtree (e.g. selecting preview text).
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);
    if (identical(_activeInstance, this)) {
      _activeInstance = null;
    }
    _editFocusNode.removeListener(_handleFocusChange);
    _previewFocusNode.removeListener(_handleFocusChange);
    _controller.removeListener(_handleControllerChange);
    _controller.dispose();
    _editFocusNode.dispose();
    _previewFocusNode.dispose();
    super.dispose();
  }

  /// Decides which surface the editor opens in. [initialViewMode] wins when
  /// provided (restoring a persisted mode), otherwise [initiallyPreview] does.
  /// A [preview] request on an empty note is downgraded to edit so a new note
  /// is immediately typable; split keeps its editable field, so it survives.
  EditorViewMode _resolveInitialViewMode(String markdown) {
    final requested = widget.initialViewMode ??
        (widget.initiallyPreview
            ? EditorViewMode.preview
            : EditorViewMode.edit);
    if (requested == EditorViewMode.preview && markdown.trim().isEmpty) {
      return EditorViewMode.edit;
    }
    return requested;
  }

  /// Claims the active-toggle slot for this editor when its field or preview
  /// takes focus. Never clears the slot on focus loss — that would break the
  /// focus-independence the global handler exists to provide.
  void _handleFocusChange() {
    if (widget.readOnly) return;
    if (_editFocusNode.hasFocus || _previewFocusNode.hasFocus) {
      _activeInstance = this;
    }
  }

  /// Rebuilds the live preview as the user types, but only in split mode where
  /// the field and preview are on screen together. In edit/preview mode the two
  /// surfaces are never visible at once, so a per-keystroke rebuild would be
  /// wasted work (and re-parse the whole document needlessly).
  void _handleControllerChange() {
    if (_viewMode == EditorViewMode.split && mounted) {
      setState(() {});
    }
  }

  /// Flips between edit and preview and moves focus so the target mode is
  /// immediately usable: the [TextField] regains focus when returning to edit,
  /// the preview subtree takes focus (which re-claims the active-toggle slot).
  /// From split, this collapses to a single full-width preview.
  void _togglePreview() {
    _activeInstance = this;
    setState(() {
      _viewMode = _viewMode == EditorViewMode.preview
          ? EditorViewMode.edit
          : EditorViewMode.preview;
    });
    widget.onViewModeChanged?.call(_viewMode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_viewMode == EditorViewMode.preview) {
        _previewFocusNode.requestFocus();
      } else {
        _editFocusNode.requestFocus();
      }
    });
  }

  /// Toggles the side-by-side split view. Leaving split returns to the plain
  /// editor; entering it puts focus in the field so typing updates the live
  /// preview immediately.
  void _toggleSplit() {
    _activeInstance = this;
    setState(() {
      _viewMode = _viewMode == EditorViewMode.split
          ? EditorViewMode.edit
          : EditorViewMode.split;
    });
    widget.onViewModeChanged?.call(_viewMode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editFocusNode.requestFocus();
    });
  }

  /// Global keyboard toggles on the Cmd (macOS) / Ctrl (Windows/Linux) + E key:
  /// * without Shift — preview⇄edit;
  /// * with Shift — the side-by-side split view.
  ///
  /// Registered on [HardwareKeyboard] so it fires regardless of where focus is,
  /// as long as this editor is mounted and owns the active-toggle slot (see
  /// [_activeInstance]). Returns true (handled) only when it toggles, so a
  /// single key press flips exactly once and no other editor also acts.
  bool _globalKeyHandler(KeyEvent event) {
    if (!mounted || widget.readOnly) return false;
    if (!identical(_activeInstance, this)) return false;
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyE) return false;
    final hasModifier = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (!hasModifier) return false;
    if (HardwareKeyboard.instance.isShiftPressed) {
      _toggleSplit();
    } else {
      _togglePreview();
    }
    return true;
  }

  // --- markdown-insert helpers ----------------------------------------------

  /// Wraps the current selection with [left] and [right] markers (e.g. `**` for
  /// bold). With a collapsed caret it inserts the two markers and places the
  /// caret between them so the user can start typing the emphasized text.
  ///
  /// Always fires [widget.onChanged] because a programmatic controller mutation
  /// does not trigger [TextField.onChanged].
  void _wrapSelection(String left, String right) {
    final value = _controller.value;
    final text = value.text;
    final selection = value.selection;

    // No valid selection (never focused): append the markers at the end.
    if (!selection.isValid) {
      final newText = '$text$left$right';
      _apply(newText, TextSelection.collapsed(offset: text.length + left.length));
      return;
    }

    final selected = text.substring(selection.start, selection.end);
    final newText =
        text.replaceRange(selection.start, selection.end, '$left$selected$right');

    final TextSelection newSelection;
    if (selection.isCollapsed) {
      newSelection =
          TextSelection.collapsed(offset: selection.start + left.length);
    } else {
      newSelection = TextSelection(
        baseOffset: selection.start + left.length,
        extentOffset: selection.end + left.length,
      );
    }
    _apply(newText, newSelection);
  }

  /// Prefixes every line spanned by the current selection with the string
  /// returned by [prefixFor] (called with the 0-based index of the line within
  /// the selected block, so ordered lists can number sequentially).
  ///
  /// The selection is expanded to whole lines first, then the resulting block is
  /// re-selected so a follow-up action still targets the same content.
  void _prefixLines(String Function(int index) prefixFor) {
    final value = _controller.value;
    final text = value.text;
    final selection = value.selection;

    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : start;

    // Expand to the start of the first line and the end of the last line.
    final lineStart = start <= 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    var lineEnd = text.indexOf('\n', end);
    if (lineEnd == -1) lineEnd = text.length;

    final block = text.substring(lineStart, lineEnd);
    final lines = block.split('\n');
    final buffer = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) buffer.write('\n');
      buffer
        ..write(prefixFor(i))
        ..write(lines[i]);
    }
    final newBlock = buffer.toString();
    final newText = text.replaceRange(lineStart, lineEnd, newBlock);

    _apply(
      newText,
      TextSelection(
        baseOffset: lineStart,
        extentOffset: lineStart + newBlock.length,
      ),
    );
  }

  /// Wraps the current selection in a fenced code block. The selected text (or
  /// an empty line, for a collapsed caret) is placed between ``` fences on their
  /// own lines.
  void _wrapCodeBlock() {
    _wrapSelection('```\n', '\n```');
  }

  /// Wraps the current selection as a Markdown link `[selected](url)` and
  /// selects the `url` placeholder so the user can immediately type the target.
  void _insertLink() {
    const placeholder = 'url';
    final value = _controller.value;
    final text = value.text;
    final selection = value.selection;

    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : start;
    final selected = text.substring(start, end);

    final replacement = '[$selected]($placeholder)';
    final newText = text.replaceRange(start, end, replacement);

    // Offset of the placeholder: '[' + selected + '](' precede it.
    final placeholderStart = start + 1 + selected.length + 2;
    _apply(
      newText,
      TextSelection(
        baseOffset: placeholderStart,
        extentOffset: placeholderStart + placeholder.length,
      ),
    );
  }

  /// Commits [newText] and [selection] to the controller and notifies the host.
  ///
  /// Programmatic controller mutations do not fire [TextField.onChanged], so
  /// [widget.onChanged] is called here explicitly.
  void _apply(String newText, TextSelection selection) {
    _controller.value = TextEditingValue(text: newText, selection: selection);
    widget.onChanged(newText);
  }

  // --- link handling --------------------------------------------------------

  void _handleTapLink(String text, String? href, String title) {
    if (href == null || href.isEmpty) return;
    final uri = Uri.tryParse(href);
    if (uri != null && uri.scheme == _internalScheme) {
      // notex://<id> — the id is the host, falling back to the path for schemes
      // parsed without an authority component.
      final id = uri.host.isNotEmpty
          ? uri.host
          : uri.path.replaceFirst(RegExp(r'^/+'), '');
      widget.onInternalLink?.call(id);
    } else {
      widget.onExternalLink?.call(href);
    }
  }

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) {
      return _buildPreview(context);
    }

    final toolbarButtons = _editVisible ? _toolbarButtons() : null;
    // The Cmd/Ctrl+E toggle is delivered globally via [_globalKeyHandler], so no
    // Focus wrapper is needed here to catch it. The preview subtree still takes
    // focus (below) so this editor claims the active-toggle slot when shown.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildControlBar(context, toolbarButtons),
        Divider(
          height: 1,
          thickness: 1,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.06),
        ),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  /// Renders the active surface(s) for [_viewMode]. Split lays the field and
  /// the live preview side by side, sharing the same [_controller] so both read
  /// and write the one source of truth.
  Widget _buildBody(BuildContext context) {
    switch (_viewMode) {
      case EditorViewMode.edit:
        return _buildEditField(context);
      case EditorViewMode.preview:
        return Focus(
          focusNode: _previewFocusNode,
          autofocus: true,
          child: _buildPreview(context),
        );
      case EditorViewMode.split:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildEditField(context)),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.06),
            ),
            Expanded(child: _buildPreview(context)),
          ],
        );
    }
  }

  /// The row holding the edit-mode insert toolbar (when applicable) and the
  /// edit⇄preview toggle. The toggle is always present outside read-only mode.
  Widget _buildControlBar(BuildContext context, List<Widget>? toolbarButtons) {
    // The modifier key differs by platform: Cmd on macOS, Ctrl elsewhere.
    final mod =
        Theme.of(context).platform == TargetPlatform.macOS ? 'Cmd' : 'Ctrl';
    return Material(
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: toolbarButtons == null || toolbarButtons.isEmpty
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: toolbarButtons,
                    ),
                  ),
          ),
          if (widget.trailing != null) widget.trailing!,
          IconButton(
            tooltip:
                '${_viewMode == EditorViewMode.split ? 'Exit split' : 'Split view'} ($mod+Shift+E)',
            icon: Icon(
              _viewMode == EditorViewMode.split
                  ? Icons.splitscreen
                  : Icons.vertical_split_outlined,
            ),
            onPressed: _toggleSplit,
          ),
          IconButton(
            tooltip:
                '${_viewMode == EditorViewMode.preview ? 'Edit' : 'Preview'} ($mod+E)',
            icon: Icon(
              _viewMode == EditorViewMode.preview
                  ? Icons.edit
                  : Icons.visibility,
            ),
            onPressed: _togglePreview,
          ),
        ],
      ),
    );
  }

  Widget _buildEditField(BuildContext context) {
    final color = widget.textColor ?? Theme.of(context).colorScheme.onSurface;
    // Wrap the field in a Focus whose onKeyEvent intercepts Tab / Shift+Tab
    // BEFORE Flutter's default focus traversal. Key events are dispatched to the
    // focused node (the field) first and then bubble up to this ancestor Focus,
    // so normal typing, arrow keys, and other shortcuts already handled by the
    // field are unaffected — only an unconsumed Tab reaches this handler.
    // skipTraversal keeps this wrapper out of the tab order itself.
    return Focus(
      skipTraversal: true,
      onKeyEvent: _handleEditKeyEvent,
      child: TextField(
        controller: _controller,
        focusNode: _editFocusNode,
        onChanged: widget.onChanged,
        maxLines: null,
        minLines: null,
        expands: true,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(
          fontSize: widget.fontSize,
          height: widget.lineHeight,
          color: color,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Start writing…',
          contentPadding: EdgeInsets.all(16),
          // Kill the default InputDecorator hover tint so the glass editor
          // background doesn't flicker when the mouse enters/leaves the field.
          hoverColor: Colors.transparent,
          fillColor: Colors.transparent,
          filled: false,
        ),
      ),
    );
  }

  // --- Tab indentation ------------------------------------------------------

  /// Number of spaces inserted for one indent level.
  static const _indent = '  ';

  /// Intercepts Tab (indent) and Shift+Tab (outdent) so they edit the text
  /// instead of moving focus. Returns [KeyEventResult.handled] for Tab to
  /// suppress traversal; every other key is ignored so the field handles it.
  KeyEventResult _handleEditKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      _outdentAtCaret();
    } else {
      _indentAtCaret();
    }
    // Always consume Tab so focus never traverses, even when outdent is a no-op.
    return KeyEventResult.handled;
  }

  /// Inserts two spaces at the caret, replacing any active selection, and keeps
  /// the caret directly after the inserted spaces.
  void _indentAtCaret() {
    final value = _controller.value;
    final text = value.text;
    final selection = value.selection;

    if (!selection.isValid) {
      final newText = '$text$_indent';
      _apply(newText, TextSelection.collapsed(offset: newText.length));
      return;
    }

    final newText =
        text.replaceRange(selection.start, selection.end, _indent);
    _apply(
      newText,
      TextSelection.collapsed(offset: selection.start + _indent.length),
    );
  }

  /// Removes up to two leading spaces (or one leading tab) from the start of the
  /// line containing the caret. If there is nothing to remove, does nothing.
  void _outdentAtCaret() {
    final value = _controller.value;
    final text = value.text;
    final selection = value.selection;

    final caret = selection.isValid ? selection.start : text.length;
    final lineStart =
        caret <= 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;

    var removeCount = 0;
    if (lineStart < text.length && text[lineStart] == '\t') {
      removeCount = 1;
    } else {
      while (removeCount < 2 &&
          lineStart + removeCount < text.length &&
          text[lineStart + removeCount] == ' ') {
        removeCount++;
      }
    }
    if (removeCount == 0) return;

    final newText = text.replaceRange(lineStart, lineStart + removeCount, '');
    final newCaret =
        (caret - removeCount).clamp(lineStart, newText.length);
    _apply(newText, TextSelection.collapsed(offset: newCaret));
  }

  Widget _buildPreview(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.textColor ?? theme.colorScheme.onSurface;
    final base = MarkdownStyleSheet.fromTheme(theme);
    final accent = theme.colorScheme.primary;
    final baseFont = widget.fontSize ?? base.p?.fontSize ?? 16.0;
    final rule = color.withValues(alpha: 0.15);
    final isDark = theme.brightness == Brightness.dark;
    // Subtle code box + monospace text in the current color — shared with the
    // Markdown page so both previews render code identically (no highlight).
    final codeStyles = MarkdownCodeStyles.from(
      isDark: isDark,
      baseFont: baseFont,
      color: color,
    );
    final styleSheet = base.copyWith(
      p: base.p?.copyWith(
        fontSize: baseFont,
        height: widget.lineHeight,
        color: color,
      ),
      h1: base.h1?.copyWith(
        fontSize: (baseFont * 1.75).roundToDouble(),
        fontWeight: FontWeight.w800,
        color: color,
      ),
      h2: base.h2?.copyWith(
        fontSize: (baseFont * 1.45).roundToDouble(),
        fontWeight: FontWeight.w700,
        color: color,
      ),
      h3: base.h3?.copyWith(
        fontSize: (baseFont * 1.2).roundToDouble(),
        fontWeight: FontWeight.w600,
        color: color,
      ),
      a: TextStyle(
        color: accent,
        decoration: TextDecoration.underline,
        decorationColor: accent.withValues(alpha: 0.5),
      ),
      // Inline code keeps the current text color and monospace font, with NO
      // background highlight — per the requested look (no "selected text" band).
      code: codeStyles.textStyle,
      // Fenced code blocks are rendered by the custom `_CodeBlockBuilder`
      // registered under the `pre` tag below, which draws the full-width box.
      // flutter_markdown_plus still wraps every `pre` builder's output in an
      // outer Container using this decoration (builder.dart:470-474), so it is
      // neutralised to an empty decoration to avoid a double box.
      codeblockDecoration: const BoxDecoration(),
      blockquote: TextStyle(
        fontSize: baseFont,
        height: widget.lineHeight,
        color: color.withValues(alpha: 0.7),
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      tableHead: TextStyle(
        fontSize: baseFont,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      tableBody: TextStyle(fontSize: baseFont, color: color),
      tableHeadAlign: TextAlign.left,
      tableBorder: TableBorder.all(
        color: rule,
        width: 1,
        borderRadius: BorderRadius.circular(8),
      ),
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      listBullet: TextStyle(
        fontSize: baseFont,
        color: accent,
        fontWeight: FontWeight.w700,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: rule, width: 1)),
      ),
    );
    return SelectionArea(
      child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: MarkdownBody(
        data: _controller.text,
        // Selection is provided by the SelectionArea wrapper below (see build).
        // flutter_markdown's own `selectable: true` cannot select the custom
        // code-block widgets, so we let SelectionArea handle the whole subtree.
        selectable: false,
        // A single newline (one Enter) renders as a real line break, matching
        // what the user typed in the editor. Without this, CommonMark collapses
        // single newlines into a space (soft break).
        softLineBreak: true,
        styleSheet: styleSheet,
        // Custom renderer for fenced code blocks (`pre`). Draws a full-width
        // box instead of the default shrink-to-content SingleChildScrollView.
        // Only affects block code — inline `code` is untouched.
        builders: {
          'pre': CodeBlockBuilder(
            textStyle: codeStyles.textStyle,
            decoration: codeStyles.decoration,
          ),
        },
        // extensionSet is intentionally left null: flutter_markdown_plus
        // defaults to markdown's ExtensionSet.gitHubFlavored, which enables
        // tables, checkbox task-lists, strikethrough, and fenced code blocks.
        // The `markdown` package is not a direct dependency, so passing the
        // constant explicitly would require importing it and trip the
        // depend_on_referenced_packages lint.
        onTapLink: _handleTapLink,
      ),
    ));
  }

  // --- toolbar --------------------------------------------------------------

  /// The insert buttons for the active [widget.toolbar] profile, or null when no
  /// toolbar should be shown ([EditorToolbarProfile.none]).
  List<Widget>? _toolbarButtons() {
    switch (widget.toolbar) {
      case EditorToolbarProfile.none:
        return null;
      case EditorToolbarProfile.full:
        return _fullToolbarButtons();
      case EditorToolbarProfile.minimal:
        return _minimalToolbarButtons();
    }
  }

  List<Widget> _fullToolbarButtons() {
    return [
      _wrapButton(Icons.format_bold, 'Bold', '**', '**'),
      _wrapButton(Icons.format_italic, 'Italic', '*', '*'),
      _wrapButton(Icons.format_strikethrough, 'Strikethrough', '~~', '~~'),
      _wrapButton(Icons.code, 'Inline code', '`', '`'),
      const VerticalDivider(width: 1),
      _headerButton('H1', 'Heading 1', '# '),
      _headerButton('H2', 'Heading 2', '## '),
      _headerButton('H3', 'Heading 3', '### '),
      const VerticalDivider(width: 1),
      _prefixButton(
        Icons.format_list_bulleted,
        'Bullet list',
        (_) => '- ',
      ),
      _prefixButton(
        Icons.format_list_numbered,
        'Numbered list',
        (index) => '${index + 1}. ',
      ),
      _prefixButton(Icons.checklist, 'Checklist', (_) => '- [ ] '),
      const VerticalDivider(width: 1),
      _iconButton(Icons.data_object, 'Code block', _wrapCodeBlock),
      _prefixButton(Icons.format_quote, 'Blockquote', (_) => '> '),
      _iconButton(Icons.link, 'Link', _insertLink),
    ];
  }

  List<Widget> _minimalToolbarButtons() {
    return [
      _wrapButton(Icons.format_bold, 'Bold', '**', '**'),
      _wrapButton(Icons.format_italic, 'Italic', '*', '*'),
      const VerticalDivider(width: 1),
      _headerButton('H1', 'Heading 1', '# '),
      _headerButton('H2', 'Heading 2', '## '),
      _headerButton('H3', 'Heading 3', '### '),
      const VerticalDivider(width: 1),
      _prefixButton(
        Icons.format_list_bulleted,
        'Bullet list',
        (_) => '- ',
      ),
      _prefixButton(
        Icons.format_list_numbered,
        'Numbered list',
        (index) => '${index + 1}. ',
      ),
    ];
  }

  Widget _wrapButton(IconData icon, String tooltip, String left, String right) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: () => _wrapSelection(left, right),
    );
  }

  Widget _prefixButton(
    IconData icon,
    String tooltip,
    String Function(int index) prefixFor,
  ) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: () => _prefixLines(prefixFor),
    );
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }

  Widget _headerButton(String label, String tooltip, String prefix) {
    return _HeaderButton(
      label: label,
      tooltip: tooltip,
      onPressed: () => _prefixLines((_) => prefix),
    );
  }
}

/// A compact text-label toolbar button used for the header-level actions.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }
}
