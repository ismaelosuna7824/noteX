import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/entities/note.dart';
import '../../domain/services/mention_trigger.dart';
import '../widgets/mention_overlay.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../state/security_state.dart';
import 'package:get_it/get_it.dart';
import '../widgets/editor_text_controls.dart';
import '../widgets/note_markdown_editor.dart';
import '../state/tiling_state.dart';
import '../widgets/tiling_layout.dart';

/// Rich text note editor with auto-save.
///
/// Built on the shared [NoteMarkdownEditor]. Content is held as
/// a [String] Markdown snapshot ([_latestMarkdown]) that the editor emits on
/// every real edit; no polling is needed because the shared widget only fires
/// `onChanged` for genuine document changes (its listener is attached after the
/// initial programmatic load).
///
/// Save indicator logic:
///   1. Any real edit (editor content or title) → [_onUserEdit] → show "Saving…".
///   2. A 2 s debounce fires after the last detected edit → [_save].
///   3. On success → show "Saved" for 2 s → hide.
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
  late TextEditingController _titleController;
  String? _loadedNoteId;

  // ── @mention picker ───────────────────────────────────────────────────
  /// The `@query` currently being composed, or null when no picker is open.
  MentionQuery? _mentionQuery;

  /// Gives the picker's keyboard handling somewhere to be driven from.
  final GlobalKey<MentionOverlayState> _mentionOverlayKey = GlobalKey();

  // ── Tiling state (singleton, persisted to disk) ─────────────────────
  TilingState get _tiling => GetIt.instance<TilingState>();

  // ── Save indicator ────────────────────────────────────────────────────
  final ValueNotifier<String> _saveStatus = ValueNotifier('');
  Timer? _debounce;
  Timer? _hideTimer;

  /// The latest Markdown emitted by the shared editor for the loaded note.
  /// Seeded with the raw stored content (the editor converts it for display)
  /// and replaced on every real edit; this snapshot is what gets persisted.
  String _latestMarkdown = '';

  /// Last content known for the loaded note, used by [didUpdateWidget] to
  /// detect an EXTERNAL change (e.g. the note edited in the notes-list preview
  /// while this page is open) and force a reload. Seeded on load with the raw
  /// stored content and advanced to the saved Markdown after each save so a
  /// self-triggered refresh does not look like an external edit.
  String _prevContent = '';

  /// Bumped on every (re)load so the [NoteMarkdownEditor]'s key changes and it
  /// remounts with fresh content — both on note switch and external refresh.
  int _reloadCount = 0;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _loadNote();
    // Register save callback so navigateToPage can flush before switching
    widget.appState.editorSaveCallback = _saveCurrentNote;
    // The picker's arrow/Enter keys must beat the TextField to the event, and
    // a Focus ancestor never would: EditableText consumes arrows before they
    // bubble. Same process-wide handler the editor uses for Cmd/Ctrl+E.
    HardwareKeyboard.instance.addHandler(_mentionKeyHandler);
  }

  /// Routes navigation keys to the mention picker while one is open.
  ///
  /// Returns false whenever no picker is showing, so ordinary typing, caret
  /// movement and every other shortcut behave exactly as before.
  bool _mentionKeyHandler(KeyEvent event) {
    if (_mentionQuery == null) return false;
    return _mentionOverlayKey.currentState?.handleKey(event) ?? false;
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
    HardwareKeyboard.instance.removeHandler(_mentionKeyHandler);
    _debounce?.cancel();
    _hideTimer?.cancel();

    final note = widget.appState.currentNote;
    if (note != null && !_tiling.isActive) {
      widget.appState.autoSaveService.forceSave(
        noteId: note.id,
        title: _titleController.text,
        content: _latestMarkdown,
      );
    }
    widget.appState.editorSaveCallback = null;
    widget.appState.autoSaveService.unwatch();
    _titleController.dispose();
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
    _saveStatus.value = '';

    _titleController.text = note.title;

    // The shared editor converts raw stored content (Delta or Markdown) for
    // display; seed the latest-Markdown snapshot with the raw content until the
    // first real edit replaces it. Bump the reload token so the editor remounts
    // with the new content (note switch or external refresh).
    _latestMarkdown = note.content;
    _prevContent = note.content;
    _reloadCount++;

    // Register for auto-save service safety net
    widget.appState.autoSaveService.watch(
      noteId: note.id,
      getTitle: () => _titleController.text,
      getContent: () => _latestMarkdown,
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
      content: _latestMarkdown,
    );
  }

  // ── Edit detection & save ─────────────────────────────────────────────

  /// Called when a real edit is detected (editor onChanged or title onChanged).
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

    final content = _latestMarkdown;
    final title = _titleController.text;

    final ok = await widget.appState.autoSaveService.forceSave(
      noteId: note.id,
      title: title,
      content: content,
    );

    if (!mounted) return;
    if (ok) {
      // Advance the external-change baseline to what we just saved so the
      // follow-up currentNote refresh isn't mistaken for an external edit.
      _prevContent = content;
      _saveStatus.value = 'saved';
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _saveStatus.value = '';
      });
    }
  }

  // ── @mention ──────────────────────────────────────────────────────────

  /// Opens, updates or closes the picker as the editor reports the token.
  ///
  /// Only rebuilds when the token actually changes, so ordinary typing outside
  /// a mention costs nothing.
  void _onMentionQuery(MentionQuery? query) {
    if (query == _mentionQuery) return;
    setState(() => _mentionQuery = query);
  }

  /// Notes offerable for [currentNoteId], newest first.
  ///
  /// Excludes the note being edited — a note linking to itself is not a link —
  /// and anything in the trash. The overlay does the query filtering.
  List<Note> _mentionCandidates(String currentNoteId) {
    final candidates = widget.appState.notes
        .where((n) => n.id != currentNoteId && n.deletedAt == null)
        .toList();
    candidates.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return candidates;
  }

  /// Replaces the composing `@query` with a Markdown link to [note].
  void _commitMention(Note note) {
    final trigger = _mentionQuery;
    if (trigger == null) return;

    final editorState = GlobalObjectKey<NoteMarkdownEditorState>(
      '${widget.appState.currentNote?.id}#$_reloadCount',
    ).currentState;

    setState(() => _mentionQuery = null);

    editorState?.commitMention(
      trigger: trigger,
      noteId: note.id,
      displayText: note.title,
    );
  }

  /// Navigate to the note targeted by a `notex://<id>` internal link tap.
  void _openInternalNote(String noteId) {
    final note = widget.appState.notes.cast<Note?>().firstWhere(
      (n) => n?.id == noteId,
      orElse: () => null,
    );
    if (note != null) {
      widget.appState.selectNote(note);
    }
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
            orElse: () => _tiling.tiledNotes.isNotEmpty
                ? _tiling.tiledNotes.first
                : currentNote,
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
            _buildEditorToolbar(
              note,
              accentColor,
              editorBg,
              chipBg,
              chipBorder,
              chipText,
              iconColor,
              isDark,
              isCompact,
              hasNoteColor,
            ),

          // Main editor area
          Expanded(
            child:
                note.isLocked &&
                    !GetIt.instance<SecurityState>().isNoteUnlocked(note.id)
                ? _buildLockedOverlay(
                    context,
                    editorBg,
                    chipBorder,
                    accentColor,
                    note.id,
                  )
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
                : Container(
                    decoration: BoxDecoration(
                      color: editorBg.withValues(alpha: bgAlpha),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: chipBorder, width: 1),
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
                    // Tight top padding: the font-size / line-height controls
                    // moved into the editor toolbar row (via `trailing`), so no
                    // extra top chrome is needed above the editor.
                    padding: EdgeInsets.fromLTRB(
                      isZen ? 32 : (isCompact ? 8 : 24),
                      isZen ? 16 : (isCompact ? 4 : 8),
                      isZen ? 32 : (isCompact ? 8 : 24),
                      isZen ? 32 : (isCompact ? 8 : 24),
                    ),
                    // Shared markdown editor widget: renders its own toolbar
                    // (full, or minimal in compact mode) + the editor. The
                    // font-size / line-height controls ride in the toolbar row
                    // via `trailing` (hidden in compact mode, as before).
                    //
                    // The Stack exists only to float the @mention picker over
                    // the editor; with no mention open it adds a single child
                    // and the layout is unchanged.
                    child: Stack(
                      children: [
                        NoteMarkdownEditor(
                          // GlobalObjectKey, not ValueKey: it keeps the same
                          // per-note identity that forces a rebuild on note switch
                          // AND exposes currentState so the picker can commit a
                          // mention back into the editor.
                          key: GlobalObjectKey<NoteMarkdownEditorState>(
                            '${note.id}#$_reloadCount',
                          ),
                          initialContent: note.content,
                          initialViewMode: EditorViewModeName.fromName(
                            widget.themeState.editorViewMode,
                          ),
                          onViewModeChanged: (mode) =>
                              widget.themeState.setEditorViewMode(mode.name),
                          autofocus: true,
                          toolbar: isCompact
                              ? EditorToolbarProfile.minimal
                              : EditorToolbarProfile.full,
                          fontSize: widget.themeState.editorFontSize,
                          lineHeight: widget.themeState.editorLineHeight,
                          textColor: noteColor != null
                              ? (noteColor.computeLuminance() > 0.5
                                    ? Colors.black87
                                    : Colors.white)
                              : widget.themeState.editorTextColor,
                          trailing: isCompact
                              ? null
                              : EditorTextControls(
                                  themeState: widget.themeState,
                                  noteColor: noteColor,
                                ),
                          onChanged: (markdown) {
                            _latestMarkdown = markdown;
                            _onUserEdit();
                          },
                          onInternalLink: _openInternalNote,
                          onExternalLink: (url) => launchUrl(Uri.parse(url)),
                          onMentionQuery: _onMentionQuery,
                        ),
                        if (_mentionQuery != null)
                          Positioned(
                            left: 0,
                            bottom: 0,
                            child: MentionOverlay(
                              key: _mentionOverlayKey,
                              notes: _mentionCandidates(note.id),
                              query: _mentionQuery!.query,
                              onSelect: _commitMention,
                              onDismiss: () =>
                                  setState(() => _mentionQuery = null),
                              accentColor: accentColor,
                              bgColor: theme.colorScheme.surface,
                              borderColor: chipBorder,
                              textColor: theme.colorScheme.onSurface,
                              mutedColor: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
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
          title: const Text(
            'Add note to tiling',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          children: [
            // Create new note option
            ListTile(
              leading: Icon(Icons.add_rounded, color: accentColor),
              title: Text(
                'Create new note',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
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
                child: Text(
                  'No existing notes available',
                  style: TextStyle(fontSize: 13, color: chipText),
                  textAlign: TextAlign.center,
                ),
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
    Note note,
    Color accentColor,
    Color editorBg,
    Color chipBg,
    Color chipBorder,
    Color chipText,
    Color iconColor,
    bool isDark,
    bool isCompact,
    bool hasNoteColor,
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
                    onChanged: (_) => _onUserEdit(),
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
                        horizontal: 12,
                        vertical: 8,
                      ),
                      prefixIcon: Icon(
                        Icons.edit_note_rounded,
                        color: iconColor.withValues(alpha: 0.6),
                        size: 18,
                      ),
                      // Save-status icon lives INSIDE the title input, at the end.
                      suffixIcon: Icon(
                        _getSyncIcon(note.syncStatus.name),
                        color: iconColor,
                        size: 16,
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
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
              // Color
              _buildColorButton(
                note,
                accentColor,
                iconColor,
                chipBg,
                chipBorder,
                size: btnSize,
                radius: btnRadius,
              ),
              const SizedBox(width: 4),
              // Share
              _buildToolbarBtn(
                icon: Icons.share_outlined,
                tooltip: 'Share note',
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
                size: btnSize,
                radius: btnRadius,
                iconSize: btnIconSize,
                iconColor: iconColor,
                chipBg: chipBg,
                chipBorder: chipBorder,
              ),
              const SizedBox(width: 4),
              // Ephemeral
              _buildToolbarBtn(
                icon: note.isEphemeral
                    ? Icons.bolt_rounded
                    : Icons.bolt_outlined,
                tooltip: note.isEphemeral
                    ? 'Quick Note (24h)'
                    : 'Make Quick Note',
                onTap: () => widget.appState.toggleEphemeral(note.id),
                size: btnSize,
                radius: btnRadius,
                iconSize: btnIconSize,
                iconColor: note.isEphemeral ? Colors.amber.shade600 : iconColor,
                chipBg: note.isEphemeral
                    ? Colors.amber.withValues(alpha: 0.15)
                    : chipBg,
                chipBorder: note.isEphemeral
                    ? Colors.amber.withValues(alpha: 0.4)
                    : chipBorder,
              ),
              const SizedBox(width: 4),
              // Lock
              _buildToolbarBtn(
                icon: note.isLocked
                    ? Icons.lock_rounded
                    : Icons.lock_open_rounded,
                tooltip: note.isLocked ? 'Unlock' : 'Lock',
                onTap: () {
                  final sec = GetIt.instance<SecurityState>();
                  if (!note.isLocked && !sec.hasPin) {
                    _showSetPinDialog(context, sec, note);
                  } else {
                    widget.appState.toggleLock(note.id);
                  }
                },
                size: btnSize,
                radius: btnRadius,
                iconSize: btnIconSize,
                iconColor: note.isLocked ? Colors.red.shade400 : iconColor,
                chipBg: note.isLocked
                    ? Colors.red.withValues(alpha: 0.15)
                    : chipBg,
                chipBorder: note.isLocked
                    ? Colors.red.withValues(alpha: 0.4)
                    : chipBorder,
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
                      content: _latestMarkdown,
                    );
                    await widget.appState.refreshNotes();
                    if (!mounted) return;
                    // Use the fresh note from DB
                    final freshNote = widget.appState.currentNote ?? note;
                    setState(
                      () => _tiling.enterTiling(initialNotes: [freshNote]),
                    );
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _showTilingNotePicker(context, accentColor);
                    });
                  }
                },
                size: btnSize,
                radius: btnRadius,
                iconSize: btnIconSize,
                iconColor: _tiling.isActive ? accentColor : iconColor,
                chipBg: _tiling.isActive
                    ? accentColor.withValues(alpha: 0.15)
                    : chipBg,
                chipBorder: _tiling.isActive
                    ? accentColor.withValues(alpha: 0.4)
                    : chipBorder,
              ),
              if (_tiling.isActive && _tiling.canAddTile) ...[
                const SizedBox(width: 4),
                _buildToolbarBtn(
                  icon: Icons.add_rounded,
                  tooltip: 'Add note',
                  onTap: () => _showTilingNotePicker(context, accentColor),
                  size: btnSize,
                  radius: btnRadius,
                  iconSize: btnIconSize,
                  iconColor: iconColor,
                  chipBg: chipBg,
                  chipBorder: chipBorder,
                ),
              ],
              if (_tiling.isActive) ...[
                const SizedBox(width: 4),
                _buildToolbarBtn(
                  icon: Icons.close_fullscreen_rounded,
                  tooltip: 'Exit Tiling',
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
                  size: btnSize,
                  radius: btnRadius,
                  iconSize: btnIconSize,
                  iconColor: iconColor,
                  chipBg: chipBg,
                  chipBorder: chipBorder,
                ),
              ],
              const SizedBox(width: 4),
              // Zen
              _buildToolbarBtn(
                icon: Icons.spa_outlined,
                tooltip: 'Focus Mode',
                onTap: () => widget.appState.enterZenMode(),
                size: btnSize,
                radius: btnRadius,
                iconSize: btnIconSize,
                iconColor: iconColor,
                chipBg: chipBg,
                chipBorder: chipBorder,
              ),
              // Compact (disabled in tiling mode)
              if (!_tiling.isActive) ...[
                const SizedBox(width: 4),
                _buildToolbarBtn(
                  icon: isCompact
                      ? Icons.fullscreen_rounded
                      : Icons.picture_in_picture_alt_outlined,
                  tooltip: isCompact ? 'Full size' : 'Compact',
                  onTap: () => isCompact
                      ? widget.appState.exitCompactMode()
                      : widget.appState.enterCompactMode(note),
                  size: btnSize,
                  radius: btnRadius,
                  iconSize: btnIconSize,
                  iconColor: iconColor,
                  chipBg: chipBg,
                  chipBorder: chipBorder,
                ),
              ],
              // Save indicator
              ValueListenableBuilder<String>(
                valueListenable: _saveStatus,
                builder: (context, status, _) {
                  if (status != 'saved') return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.check_circle_outline_rounded,
                      size: 14,
                      color: isDark
                          ? Colors.green.shade300
                          : Colors.green.shade600,
                    ),
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your PIN to view this note',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
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
                      child: Text(
                        error,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                if (securityState.verifyAndUnlock(
                  noteId,
                  _lockPinController.text,
                )) {
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
            : Icon(Icons.palette_outlined, size: size * 0.41, color: iconColor),
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
            const Text(
              'Set a PIN to lock notes. You\'ll need this PIN to view locked notes.',
            ),
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
                      child: Text(
                        error,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
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
