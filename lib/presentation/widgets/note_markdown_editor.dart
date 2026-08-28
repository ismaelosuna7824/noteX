import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/services/markdown_task_toggle.dart';
import '../../domain/services/mention_trigger.dart';
import '../../domain/services/note_link_parser.dart';
import '../../infrastructure/content/note_content_format.dart';
import '../utils/app_shortcuts.dart';
import 'markdown/notex_markdown_view.dart';
import 'typing_ink_controller.dart';

/// Toggles between edit and preview — see [NoteMarkdownEditorState._togglePreview].
class _TogglePreviewIntent extends Intent {
  const _TogglePreviewIntent();
}

/// Toggles the side-by-side split view — see [NoteMarkdownEditorState._toggleSplit].
class _ToggleSplitIntent extends Intent {
  const _ToggleSplitIntent();
}

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
/// rendered preview (via [NoteXMarkdownView]) with an edit⇄preview toggle.
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
    this.onMentionQuery,
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

  /// Called as the user types with the `@mention` token under the caret, or
  /// null when no mention is open.
  ///
  /// The editor only *reports* the token — it does not search notes or render
  /// a picker. The hosting surface decides what to show and calls
  /// [NoteMarkdownEditorState.commitMention] when the user picks something,
  /// so this widget stays free of any note-repository dependency.
  final ValueChanged<MentionQuery?>? onMentionQuery;

  @override
  State<NoteMarkdownEditor> createState() => NoteMarkdownEditorState();
}

class NoteMarkdownEditorState extends State<NoteMarkdownEditor> {
  late final TypingInkController _controller;

  /// Focus node for the edit [TextField], so a Cmd/Ctrl+E toggle from preview
  /// back to edit can immediately return focus to the field for typing.
  final FocusNode _editFocusNode = FocusNode();

  /// Focus node for the preview subtree. It takes focus while the preview
  /// shows, so the editor's local Shortcuts (see [build]) keeps receiving the
  /// Cmd/Ctrl+E toggle while the preview is what the user is looking at.
  final FocusNode _previewFocusNode = FocusNode();

  /// Which surface(s) this editor currently shows (edit / preview / split).
  EditorViewMode _viewMode = EditorViewMode.edit;

  /// The source field is visible in both edit and split modes.
  bool get _editVisible => _viewMode != EditorViewMode.preview;

  /// The rendered preview is visible in both preview and split modes.
  bool get _previewVisible => _viewMode != EditorViewMode.edit;

  /// True when the source field is not on screen, so there is nothing to focus.
  bool get _previewOnly => _viewMode == EditorViewMode.preview;

  @override
  void initState() {
    super.initState();
    // Seed the controller programmatically. Setting the controller's text here
    // does NOT invoke TextField.onChanged, so opening a note never fires
    // widget.onChanged. Only real user typing (and explicit toolbar inserts)
    // do.
    final markdown = NoteContentFormat.ensureMarkdown(widget.initialContent);
    _controller = TypingInkController(text: markdown);
    _viewMode = _resolveInitialViewMode(markdown);
    // In split mode the preview reads _controller.text directly, but user typing
    // fires TextField.onChanged (the host callback) — not setState here. So the
    // preview would go stale. Listen to the controller and rebuild live, but
    // ONLY in split mode where both surfaces are on screen at once.
    _controller.addListener(_handleControllerChange);

    // The primary editor takes focus on mount, so the Cmd/Ctrl+E toggle (see
    // [build]'s local Shortcuts) works immediately without a click — even
    // when it opens in edit or split, which (unlike preview) do not
    // auto-focus a surface.
    if (widget.autofocus && !widget.readOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_viewMode == EditorViewMode.preview) {
          _previewFocusNode.requestFocus();
        } else {
          _editFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
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
    final requested =
        widget.initialViewMode ??
        (widget.initiallyPreview
            ? EditorViewMode.preview
            : EditorViewMode.edit);
    if (requested == EditorViewMode.preview && markdown.trim().isEmpty) {
      return EditorViewMode.edit;
    }
    return requested;
  }

  /// Rebuilds whenever the preview is on screen and the document moves under
  /// it — in split mode as the user types, in preview mode when the preview
  /// changes the document itself by ticking a checkbox.
  ///
  /// This used to fire in split mode alone, on the reasoning that preview mode
  /// hides the field so nothing could change the text. Pressable checkboxes
  /// ended that: the preview is now an editing surface too. Without this, a
  /// ticked box kept its old state until something unrelated — the autosave
  /// indicator, a resize — happened to rebuild the editor, so the first click
  /// looked like it had been ignored.
  ///
  /// Edit mode is still excluded, and for the original reason: the preview is
  /// not on screen, so re-parsing the document on every keystroke would buy
  /// nothing.
  void _handleControllerChange() {
    if (_previewVisible && mounted) {
      setState(() {});
    }
  }

  /// Flips between edit and preview and moves focus so the target mode is
  /// immediately usable: the [TextField] regains focus when returning to edit,
  /// the preview subtree takes focus (keeping the toggle reachable via the
  /// local Shortcuts in [build]). From split, this collapses to a single
  /// full-width preview.
  void _togglePreview() {
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
      _apply(
        newText,
        TextSelection.collapsed(offset: text.length + left.length),
      );
      return;
    }

    final selected = text.substring(selection.start, selection.end);
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      '$left$selected$right',
    );

    final TextSelection newSelection;
    if (selection.isCollapsed) {
      newSelection = TextSelection.collapsed(
        offset: selection.start + left.length,
      );
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

  /// Inserts a mermaid block — a working one, not an empty fence.
  ///
  /// The syntax is the whole barrier here: someone who has never written a
  /// diagram cannot start from ``` and a blank line. A two-node flowchart
  /// renders the moment it lands, so the preview teaches the shape by example
  /// and the labels are there to be typed over.
  ///
  /// An existing selection is wrapped instead, because the other reason to
  /// press this button is having just pasted mermaid source from somewhere
  /// else.
  void _insertMermaid() {
    final value = _controller.value;
    final selection = value.selection;

    if (selection.isValid && !selection.isCollapsed) {
      _wrapSelection('```mermaid\n', '\n```');
      return;
    }

    const label = 'Start';
    const block = '```mermaid\nflowchart TD\n    A[$label] --> B[End]\n```';

    final text = value.text;
    final at = selection.isValid ? selection.start : text.length;

    // Fences need their own line, or the block is swallowed by the paragraph
    // above it.
    final before = at > 0 && !text.substring(0, at).endsWith('\n') ? '\n' : '';
    final after = at < text.length && !text.substring(at).startsWith('\n')
        ? '\n'
        : '';

    final replacement = '$before$block$after';
    final newText = text.replaceRange(at, at, replacement);

    // Land on the first label rather than after the block: the next useful
    // keystroke is renaming a node, and it is already selected.
    final labelStart = at + before.length + block.indexOf(label);
    _apply(
      newText,
      TextSelection(
        baseOffset: labelStart,
        extentOffset: labelStart + label.length,
      ),
    );
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

    // Hand focus back to the field. A toolbar button is a Material button, so
    // pressing one takes focus — and an editor whose text just changed while
    // the focus sits on a button is an editor where Cmd/Ctrl+Z goes nowhere,
    // because undo is dispatched to whatever is focused. The reader has to
    // click back into the text before they can take the insert back, which is
    // the one moment they are most likely to want to.
    //
    // Returning focus rather than making the toolbar unfocusable keeps the
    // buttons reachable by keyboard, and it is what the action means anyway:
    // every caller here writes into the document, so the document is where
    // the caret belongs afterwards.
    if (_previewOnly) return;
    _editFocusNode.requestFocus();
  }

  // --- link handling --------------------------------------------------------

  void _handleTapLink(String href) {
    if (href.isEmpty) return;
    // Resolved through NoteLinkParser rather than re-parsed here, so tapping a
    // link and indexing a backlink can never disagree about which note an
    // href addresses.
    final noteId = NoteLinkParser.noteIdFromHref(href);
    if (noteId != null) {
      widget.onInternalLink?.call(noteId);
    } else {
      widget.onExternalLink?.call(href);
    }
  }

  // --- @mention -------------------------------------------------------------

  /// Forwards user typing to the host and reports the mention under the caret.
  ///
  /// Only reached for real user input: programmatic controller mutations do not
  /// fire [TextField.onChanged], so loading a note never opens a picker.
  void _handleChanged(String value) {
    widget.onChanged(value);
    _reportMentionQuery();
  }

  void _reportMentionQuery() {
    final onMentionQuery = widget.onMentionQuery;
    if (onMentionQuery == null) return;

    final selection = _controller.selection;
    // A range selection has no single caret to compose at, and an invalid
    // offset means the field has not been placed yet.
    if (!selection.isValid || !selection.isCollapsed) {
      onMentionQuery(null);
      return;
    }

    onMentionQuery(
      MentionTrigger.detect(
        text: _controller.text,
        caret: selection.baseOffset,
      ),
    );
  }

  /// Replaces the mention being composed with a link to [noteId].
  ///
  /// Called by the hosting surface once the user picks a note from its picker.
  /// Mutating the controller programmatically does not fire
  /// [TextField.onChanged], so [widget.onChanged] is invoked explicitly — the
  /// same contract the toolbar inserts follow.
  void commitMention({
    required MentionQuery trigger,
    required String noteId,
    required String displayText,
  }) {
    final insertion = MentionTrigger.complete(
      text: _controller.text,
      trigger: trigger,
      noteId: noteId,
      displayText: displayText,
    );

    _controller.value = TextEditingValue(
      text: insertion.text,
      selection: TextSelection.collapsed(offset: insertion.caret),
    );
    widget.onChanged(insertion.text);
    widget.onMentionQuery?.call(null);
  }

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) {
      return _buildPreview(context);
    }

    final toolbarButtons = _editVisible ? _toolbarButtons() : null;
    // Cmd/Ctrl+E (preview⇄edit) and Cmd/Ctrl+Shift+E (split) are scoped to
    // this editor's own subtree via Shortcuts/Actions — Flutter's own
    // focus-scoped dispatch is what makes only the currently-focused editor
    // react when several are mounted (e.g. tiling panels), replacing the
    // hand-rolled "active instance" guard this editor used to need. Both the
    // Cmd (macOS) and Ctrl (Windows/Linux) modifiers are accepted regardless
    // of the running platform, matching this shortcut's long-standing
    // behavior (unlike the app-wide shortcuts, which use one platform-correct
    // modifier — see `AppShortcuts`).
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyE, meta: true):
            _TogglePreviewIntent(),
        SingleActivator(LogicalKeyboardKey.keyE, control: true):
            _TogglePreviewIntent(),
        SingleActivator(LogicalKeyboardKey.keyE, meta: true, shift: true):
            _ToggleSplitIntent(),
        SingleActivator(LogicalKeyboardKey.keyE, control: true, shift: true):
            _ToggleSplitIntent(),
      },
      child: Actions(
        actions: {
          _TogglePreviewIntent: CallbackAction<_TogglePreviewIntent>(
            onInvoke: (_) {
              _togglePreview();
              return null;
            },
          ),
          _ToggleSplitIntent: CallbackAction<_ToggleSplitIntent>(
            onInvoke: (_) {
              _toggleSplit();
              return null;
            },
          ),
        },
        child: Column(
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
        ),
      ),
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
    // The modifier glyph/label for the running platform (⌘ on macOS, "Ctrl"
    // elsewhere) — the same [primaryModifierLabel] every other shortcut hint
    // in the app reads from (the sidebar's numbered sections, the ⌘/ help
    // sheet, the Settings shortcuts list), so this editor's own tooltips
    // never show a different modifier than the rest of the UI. Deliberately
    // NOT `Theme.of(context).platform`: that value is overridable per
    // subtree for styling purposes and can disagree with the actual running
    // platform, whereas `primaryModifierLabel` (via `defaultTargetPlatform`)
    // reflects the real platform whose physical keyboard sends Cmd or Ctrl —
    // the same source `AppShortcuts.isPrimaryModifierMeta` uses to decide
    // which modifier this editor's own Cmd/Ctrl+E binding actually expects.
    final mod = primaryModifierLabel;
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
      // The ink wash fades frame by frame, so the field has to rebuild frame by
      // frame while it does. Listening to the controller itself would drag the
      // split-mode preview through the same ~70 rebuilds for a change it cannot
      // render, so the fade gets its own narrower signal.
      child: ListenableBuilder(
        listenable: _controller.ink,
        builder: (context, _) => TextField(
          controller: _controller,
          focusNode: _editFocusNode,
          onChanged: _handleChanged,
          maxLines: null,
          minLines: null,
          expands: true,
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
          // A block caret rather than a hairline. It belongs with the ink
          // wash: the wash says what was just written and the block says where
          // the next character lands, and at a hairline's width that second
          // half is invisible the moment the caret jumps to a new line.
          cursorWidth: (widget.fontSize ?? 15) * 0.5,
          cursorRadius: const Radius.circular(2),
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

    final newText = text.replaceRange(selection.start, selection.end, _indent);
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
    final lineStart = caret <= 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;

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
    final newCaret = (caret - removeCount).clamp(lineStart, newText.length);
    _apply(newText, TextSelection.collapsed(offset: newCaret));
  }

  Widget _buildPreview(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.textColor ?? theme.colorScheme.onSurface;

    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        // One renderer for every surface in the app. The style below is all
        // this preview gets to decide; which Markdown features exist is
        // settled once, in NoteXMarkdownView.
        child: NoteXMarkdownView(
          data: _controller.text,
          onTapLink: _handleTapLink,
          // A read-only surface still draws the state of every box; what it
          // withholds is the ability to change it.
          onToggleTask: widget.readOnly ? null : _handleToggleTask,
          style: NoteXMarkdownStyle(
            isDark: theme.brightness == Brightness.dark,
            baseFontSize: widget.fontSize ?? 16.0,
            lineHeight: widget.lineHeight ?? 1.5,
            textColor: color,
            accentColor: theme.colorScheme.primary,
            surfaceColor: theme.colorScheme.surface,
          ),
        ),
      ),
    );
  }

  /// Flips the task the reader pressed in the preview.
  ///
  /// The preview counts checkboxes in document order and so does
  /// [MarkdownTaskToggle]; nothing has to be threaded between them for the two
  /// to agree on which task was meant.
  ///
  /// The selection survives untouched because the edit cannot move it: `[ ]`
  /// and `[x]` are the same length, so every offset after the change still
  /// addresses the character it did before.
  void _handleToggleTask(int index) {
    final next = MarkdownTaskToggle.toggle(_controller.text, index);
    // Null means the tap addressed a task that is no longer there — the text
    // changed under it. Leaving the document alone is the only safe answer.
    if (next == null) return;
    _apply(next, _controller.selection);
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
      _prefixButton(Icons.format_list_bulleted, 'Bullet list', (_) => '- '),
      _prefixButton(
        Icons.format_list_numbered,
        'Numbered list',
        (index) => '${index + 1}. ',
      ),
      _prefixButton(Icons.checklist, 'Checklist', (_) => '- [ ] '),
      const VerticalDivider(width: 1),
      _iconButton(Icons.data_object, 'Code block', _wrapCodeBlock),
      _iconButton(Icons.account_tree, 'Mermaid diagram', _insertMermaid),
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
      _prefixButton(Icons.format_list_bulleted, 'Bullet list', (_) => '- '),
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
    return IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: onPressed);
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
