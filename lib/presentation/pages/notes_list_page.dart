import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/note_project.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../state/security_state.dart';
import 'package:get_it/get_it.dart';
import '../utils/platform_utils.dart';
import '../widgets/animated_dialog.dart';
import '../widgets/glassmorphic_container.dart';
import '../widgets/note_grid_card.dart';

/// Notes list view with inline edit panel.
///
/// Left: scrollable note list. Right: live editor for the selected note.
class NotesListPage extends StatefulWidget {
  final AppState appState;
  final ThemeState themeState;

  const NotesListPage({
    super.key,
    required this.appState,
    required this.themeState,
  });

  @override
  State<NotesListPage> createState() => _NotesListPageState();
}

class _NotesListPageState extends State<NotesListPage> {
  QuillController? _quillController;
  late TextEditingController _titleController;
  String? _loadedNoteId;

  final FocusNode _editorFocusNode = FocusNode();

  // ── Auto-save state ──────────────────────────────────────────────────
  final ValueNotifier<String> _saveStatus = ValueNotifier('');
  Timer? _debounce;
  Timer? _hideTimer;
  Timer? _editPoller;
  String _prevContent = '';
  String _prevTitle = '';
  int _prevDocLength = 0;

  // ignore: experimental_member_use
  static final _controllerConfig = QuillControllerConfig(
    // ignore: experimental_member_use
    clipboardConfig: QuillClipboardConfig(
      // ignore: experimental_member_use
      enableExternalRichPaste: false,
    ),
  );

  bool _isGridMode = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _isGridMode = widget.themeState.notesDisplayMode == 'grid';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hideTimer?.cancel();
    _editPoller?.cancel();

    // Force-save the note that is actually loaded in the editor (not
    // necessarily currentNote, which may already point to a different note
    // if e.g. compact mode was triggered from another card).
    if (_loadedNoteId != null && _quillController != null) {
      widget.appState.autoSaveService.forceSave(
        noteId: _loadedNoteId!,
        title: _titleController.text,
        content: _serializeContent(),
      );
    }
    widget.appState.autoSaveService.unwatch();

    _quillController?.dispose();
    _titleController.dispose();
    _editorFocusNode.dispose();
    _saveStatus.dispose();
    super.dispose();
  }

  // ── Note loading ────────────────────────────────────────────────────

  void _loadNote() {
    final note = widget.appState.currentNote;
    if (note == null || note.id == _loadedNoteId) return;

    // Force-save previous note before switching.
    if (_loadedNoteId != null && _quillController != null) {
      final prevId = _loadedNoteId!;
      widget.appState.autoSaveService.forceSave(
        noteId: prevId,
        title: _titleController.text,
        content: _serializeContent(),
      );
    }

    _debounce?.cancel();
    _hideTimer?.cancel();
    _editPoller?.cancel();
    _saveStatus.value = '';
    widget.appState.autoSaveService.unwatch();

    _loadedNoteId = note.id;
    _titleController.text = note.title;

    _quillController?.dispose();
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

    // Initialize snapshots for edit detection.
    _prevContent = _serializeContent();
    _prevTitle = _titleController.text;
    _prevDocLength = _quillController!.document.length;

    // Register with auto-save service.
    widget.appState.autoSaveService.watch(
      noteId: note.id,
      getTitle: () => _titleController.text,
      getContent: _serializeContent,
    );

    // Start polling for edits.
    _editPoller = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _pollForEdits(),
    );
  }

  // ── Edit detection & save ────────────────────────────────────────────

  String _serializeContent() =>
      jsonEncode(_quillController!.document.toDelta().toJson());

  void _pollForEdits() {
    if (!mounted || _quillController == null) return;
    final title = _titleController.text;
    final doc = _quillController!.document;

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

  void _onUserEdit() {
    if (!mounted) return;
    _hideTimer?.cancel();
    _saveStatus.value = '';
    widget.appState.autoSaveService.markDirty();
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), _save);
  }

  Future<void> _save() async {
    if (!mounted) return;
    final noteId = _loadedNoteId;
    if (noteId == null || _quillController == null) return;

    final content = _serializeContent();
    final title = _titleController.text;

    final ok = await widget.appState.autoSaveService.forceSave(
      noteId: noteId,
      title: title,
      content: content,
    );

    if (!mounted) return;
    _prevContent = content;
    _prevTitle = title;
    if (ok) {
      _saveStatus.value = 'saved';
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _saveStatus.value = '';
      });
    }
  }

  void _toggleViewMode() {
    // Force-save current note before switching modes.
    if (_loadedNoteId != null && _quillController != null) {
      widget.appState.autoSaveService.forceSave(
        noteId: _loadedNoteId!,
        title: _titleController.text,
        content: _serializeContent(),
      );
    }
    setState(() {
      _isGridMode = !_isGridMode;
      widget.themeState.setNotesDisplayMode(_isGridMode ? 'grid' : 'list');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = widget.themeState.accentColor;

    // Reload editor if note changed (only in list mode)
    if (!_isGridMode && widget.appState.currentNote?.id != _loadedNoteId) {
      _loadNote();
    }

    final showPinned = widget.appState.showPinnedTab;
    final displayedNotes = showPinned
        ? widget.appState.pinnedNotes
        : widget.appState.filteredNotes;

    if (_isGridMode) {
      return _buildGridLayout(context, theme, accentColor, showPinned, displayedNotes);
    }

    return _buildListLayout(context, theme, accentColor, showPinned, displayedNotes);
  }

  // ── Shared header ──────────────────────────────────────────────────

  Widget _buildHeader(ThemeData theme, Color accentColor, bool showPinned) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 250;
        return Row(
          children: [
            Flexible(
              child: Text(
                'My Notes',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // All / Pinned tab toggle
            Container(
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTabBtn(
                    icon: Icons.list_rounded,
                    label: _isGridMode && !isCompact ? 'All' : '',
                    isSelected: !showPinned,
                    accentColor: accentColor,
                    onTap: () => widget.appState.setShowPinnedTab(false),
                  ),
                  _buildTabBtn(
                    icon: Icons.push_pin_rounded,
                    label: _isGridMode && !isCompact ? 'Pinned' : '',
                    isSelected: showPinned,
                    accentColor: accentColor,
                    onTap: () => widget.appState.setShowPinnedTab(true),
                  ),
                ],
              ),
            ),
            // List / Grid toggle — hidden when too compact
            if (!isCompact) ...[
              const SizedBox(width: 6),
              Container(
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTabBtn(
                      icon: Icons.view_list_rounded,
                      label: '',
                      isSelected: !_isGridMode,
                      accentColor: accentColor,
                      onTap: () { if (_isGridMode) _toggleViewMode(); },
                    ),
                    _buildTabBtn(
                      icon: Icons.grid_view_rounded,
                      label: '',
                      isSelected: _isGridMode,
                      accentColor: accentColor,
                      onTap: () { if (!_isGridMode) _toggleViewMode(); },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(width: 6),
        InkWell(
          onTap: () => _showImportDialog(context, accentColor),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Tooltip(
              message: 'Import from share link',
              child: Icon(
                Icons.download_rounded,
                color: accentColor,
                size: 16,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: 'Quick Note',
          child: InkWell(
            onTap: () async {
              await widget.appState.createQuickNote();
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.amber.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: 'New Note',
          child: InkWell(
            onTap: () async {
              await widget.appState.createNewNote();
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.add,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
        ],
      );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool showPinned) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            showPinned ? Icons.push_pin_outlined : Icons.note_alt_outlined,
            size: 40,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 8),
          Text(
            showPinned
                ? 'No pinned notes'
                : (widget.appState.searchQuery.isEmpty
                      ? 'No notes yet'
                      : 'No notes found'),
            style: TextStyle(
              color: theme.brightness == Brightness.dark
                  ? Colors.white70
                  : Colors.grey.shade400,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ── List layout (original) ─────────────────────────────────────────

  Widget _buildListLayout(
    BuildContext context,
    ThemeData theme,
    Color accentColor,
    bool showPinned,
    List<Note> displayedNotes,
  ) {
    // For pinned mode, fall back to the simple empty state when there's
    // nothing pinned — the tree (which always renders "+ New folder")
    // wouldn't make sense here.
    final showEmpty =
        showPinned && widget.appState.pinnedNotes.isEmpty;

    final listPanel = GlassmorphicContainer(
      borderRadius: 20,
      color: widget.themeState.editorBgColor,
      opacity: theme.brightness == Brightness.dark ? 0.90 : 0.92,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildHeader(theme, accentColor, showPinned),
          const SizedBox(height: 8),
          Expanded(
            child: showEmpty
                ? _buildEmptyState(theme, showPinned)
                : _buildUnifiedTree(theme, accentColor, showPinned),
          ),
        ],
      ),
    );

    // On mobile: full-width list only (no side-by-side editor)
    if (kIsMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: listPanel,
      );
    }

    // Desktop: side-by-side list + editor
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          SizedBox(width: 320, child: listPanel),
          const SizedBox(width: 16),
          Expanded(child: _buildEditorPanel(context, theme, accentColor)),
        ],
      ),
    );
  }

  // ── Grid layout ────────────────────────────────────────────────────

  Widget _buildGridLayout(
    BuildContext context,
    ThemeData theme,
    Color accentColor,
    bool showPinned,
    List<Note> displayedNotes,
  ) {
    final padding = kIsMobile
        ? const EdgeInsets.fromLTRB(12, 0, 12, 12)
        : const EdgeInsets.fromLTRB(16, 0, 16, 16);
    return Padding(
      padding: padding,
      child: GlassmorphicContainer(
        borderRadius: 20,
        color: widget.themeState.editorBgColor,
        opacity: theme.brightness == Brightness.dark ? 0.90 : 0.92,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildHeader(theme, accentColor, showPinned),
            const SizedBox(height: 8),
            Expanded(
              child: displayedNotes.isEmpty
                  ? _buildEmptyState(theme, showPinned)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = (constraints.maxWidth / 280)
                            .clamp(2, 5)
                            .toInt();
                        return MasonryGridView.builder(
                          key: ValueKey(
                            '${showPinned ? 'pinned' : 'all'}-grid',
                          ),
                          gridDelegate:
                              SliverSimpleGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                          ),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          itemCount: displayedNotes.length,
                          itemBuilder: (context, index) {
                            final note = displayedNotes[index];
                            return _StaggeredEntry(
                              index: index,
                              child: NoteGridCard(
                                note: note,
                                accentColor: accentColor,
                                editorBgColor:
                                    widget.themeState.editorBgColor,
                                isNoteUnlocked:
                                    GetIt.instance<SecurityState>().isNoteUnlocked(note.id),
                                onTap: () {
                                  final sec = GetIt.instance<SecurityState>();
                                  if (note.isLocked && !sec.isNoteUnlocked(note.id)) {
                                    _showUnlockDialog(context, sec, note.id, () {
                                      widget.appState.selectNote(note);
                                      if (kIsMobile) {
                                        widget.appState.navigateToPage(2);
                                      }
                                    });
                                    return;
                                  }
                                  widget.appState.selectNote(note);
                                  if (kIsMobile) {
                                    widget.appState.navigateToPage(2);
                                  }
                                },
                                onCompactMode: kIsMobile
                                    ? null
                                    : () => widget.appState.enterCompactMode(note),
                                onPin: () =>
                                    widget.appState.togglePin(note),
                                onDelete: () =>
                                    widget.appState.deleteNote(note.id),
                                onDuplicate: () =>
                                    widget.appState.duplicateNote(note),
                                noteProjects: widget.appState.noteProjects,
                                onChangeProject: (projectId) =>
                                    widget.appState.updateNoteProject(
                                        note.id, projectId),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Unified vertical tree that shows folders AND their notes as a single
  /// file-explorer-style hierarchy. Clicking a folder toggles expand/collapse;
  /// clicking a note opens it in the editor.
  Widget _buildUnifiedTree(
    ThemeData theme,
    Color accentColor,
    bool showPinned,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final state = widget.appState;
    final currentNoteId = state.currentNote?.id;
    final selectedFolderId = state.selectedNoteProjectId;
    final rows = <Widget>[];

    if (showPinned) {
      for (final n in state.pinnedNotes) {
        rows.add(_buildNoteRow(n, 0, isDark, accentColor, currentNoteId,
            guides: const []));
      }
    } else if (state.searchQuery.isNotEmpty) {
      // Flat list of search results — no folder hierarchy.
      for (final n in state.filteredNotes) {
        rows.add(_buildNoteRow(n, 0, isDark, accentColor, currentNoteId,
            guides: const []));
      }
    } else {
      // "All" pseudo-row at the top represents the root scope. Click to
      // deselect any folder so new notes / sub-folders land at root.
      // Hover-revealed actions let users create a root note or folder from
      // the top of the tree — no need to scroll past a long list to reach
      // the "+ New folder" row at the bottom.
      rows.add(_FolderTreeRow(
        label: 'All',
        depth: 0,
        guides: const [],
        color: accentColor,
        isDark: isDark,
        // Only one row in the tree ever shows as selected: when a note is
        // open, the note wins (it's the "child" / most-specific selection).
        // The folder filter context is still tracked under the hood so new
        // notes / folders land in the right place.
        isSelected: selectedFolderId == null && currentNoteId == null,
        hasChildren: false,
        isExpanded: false,
        count: 0,
        leadingIcon: Icons.inbox_rounded,
        onTap: () => state.filterByNoteProject(null),
        // Switch to root scope first so the underlying creators don't inherit
        // a previously selected folder as the parent.
        onCreateNote: () {
          state.filterByNoteProject(null);
          state.createNewNote();
        },
        onCreateSubfolder: () {
          state.filterByNoteProject(null);
          _showCreateProjectDialog(accentColor);
        },
        alwaysShowActions: true,
        onNoteDropped: (note) =>
            widget.appState.updateNoteProject(note.id, null),
      ));
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Container(
          height: 1,
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ));
      _appendTreeNodes(rows, null, 0, isDark, accentColor, currentNoteId,
          selectedFolderId, const []);
    }

    rows.add(_NewFolderRow(
      isDark: isDark,
      onTap: () => _showCreateProjectDialog(accentColor),
    ));

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  /// Recursively appends folder + note rows for the given [parentId] level.
  ///
  /// [ancestorContinues] has length == [depth]; index `i` holds
  /// `!isLastInLevel` of the depth-`i` ancestor on this branch. For a row at
  /// depth D, column k's pass-through (k in [0, D-2]) reflects whether the
  /// depth-(k+1) ancestor still has siblings below — i.e., ancestorContinues
  /// at index k+1. Index 0 is the root ancestor's flag and is never read by a
  /// column (root items have no parent column to draw a trunk through).
  void _appendTreeNodes(
    List<Widget> rows,
    String? parentId,
    int depth,
    bool isDark,
    Color accentColor,
    String? currentNoteId,
    String? selectedFolderId,
    List<bool> ancestorContinues,
  ) {
    final state = widget.appState;
    final folders = state.childFoldersOf(parentId);
    final notes = state.notesInFolder(parentId);

    // Build the per-row guide list: pass-through guides for ancestors, then a
    // terminal tee (├) or ell (└) at the immediate-parent column.
    List<_GuideKind> guidesFor(bool isLastInLevel) {
      if (depth == 0) return const [];
      return [
        for (var idx = 0; idx < depth - 1; idx++)
          ancestorContinues[idx + 1] ? _GuideKind.vertical : _GuideKind.none,
        isLastInLevel ? _GuideKind.ell : _GuideKind.tee,
      ];
    }

    for (var i = 0; i < folders.length; i++) {
      final folder = folders[i];
      final children = state.childFoldersOf(folder.id);
      final notesIn = state.notesInFolder(folder.id);
      final hasChildren = children.isNotEmpty || notesIn.isNotEmpty;
      final isExpanded = state.isFolderExpanded(folder.id);
      // Folders come before notes in render order, so a folder is "last in
      // level" only if it's the final folder AND there are no notes after.
      final isLastInLevel = (i == folders.length - 1) && notes.isEmpty;

      rows.add(
        GestureDetector(
          onSecondaryTapUp: (details) =>
              _showProjectContextMenu(details.globalPosition, folder),
          child: _FolderTreeRow(
            label: folder.name,
            depth: depth,
            guides: guidesFor(isLastInLevel),
            color: folder.color,
            isDark: isDark,
            // Folder shows as selected only while no note is open — the
            // currently-open note wins as the single visible selection.
            isSelected:
                selectedFolderId == folder.id && currentNoteId == null,
            hasChildren: hasChildren,
            isExpanded: isExpanded,
            count: state.noteCountInScope(folder.id),
            leadingIcon: Icons.folder_rounded,
            // Clicking the row selects the folder (so new notes / sub-folders
            // land here). If the folder has children and isn't expanded yet,
            // also expand it for convenience.
            onTap: () {
              state.filterByNoteProject(folder.id);
              if (hasChildren && !isExpanded) {
                state.toggleFolderExpanded(folder.id);
              }
            },
            // Chevron is its own hit target — only toggles expand, never
            // changes the selection.
            onChevronTap: hasChildren
                ? () => state.toggleFolderExpanded(folder.id)
                : null,
            onLongPress: () => _showDeleteProjectDialog(folder),
            // Inline hover actions: create a note or sub-folder directly
            // inside *this* folder, no matter what's currently selected.
            onCreateNote: () => state.createNewNote(projectId: folder.id),
            onCreateSubfolder: () =>
                _showCreateProjectDialog(accentColor, parent: folder),
            onNoteDropped: (note) =>
                widget.appState.updateNoteProject(note.id, folder.id),
          ),
        ),
      );

      if (hasChildren && isExpanded) {
        _appendTreeNodes(
          rows,
          folder.id,
          depth + 1,
          isDark,
          accentColor,
          currentNoteId,
          selectedFolderId,
          [...ancestorContinues, !isLastInLevel],
        );
      }
    }

    for (var j = 0; j < notes.length; j++) {
      final note = notes[j];
      final isLastInLevel = (j == notes.length - 1);
      rows.add(_buildNoteRow(
          note, depth, isDark, accentColor, currentNoteId,
          guides: guidesFor(isLastInLevel)));
    }
  }

  Widget _buildNoteRow(
    Note note,
    int depth,
    bool isDark,
    Color accentColor,
    String? currentNoteId, {
    required List<_GuideKind> guides,
  }) {
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showNoteContextMenu(details.globalPosition, note),
      child: _NoteTreeRow(
        note: note,
        depth: depth,
        guides: guides,
        isDark: isDark,
        accentColor: accentColor,
        isSelected: note.id == currentNoteId,
        onTap: () => _openNote(note),
      ),
    );
  }

  void _openNote(Note note) {
    // Selecting a note also focuses its parent folder so subsequent "new
    // note" / "new folder" actions land alongside it.
    widget.appState.filterByNoteProject(note.projectId);

    final sec = GetIt.instance<SecurityState>();
    if (note.isLocked && !sec.isNoteUnlocked(note.id)) {
      _showUnlockDialog(context, sec, note.id, () {
        widget.appState.previewNote(note);
        if (kIsMobile) {
          widget.appState.navigateToPage(2);
        } else {
          setState(() => _loadNote());
        }
      });
      return;
    }
    widget.appState.previewNote(note);
    if (kIsMobile) {
      widget.appState.navigateToPage(2);
    } else {
      setState(() => _loadNote());
    }
  }

  void _showNoteContextMenu(Offset position, Note note) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'pin',
          child: Row(
            children: [
              Icon(
                note.isPinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                size: 16,
                color: Colors.grey.shade400,
              ),
              const SizedBox(width: 8),
              Text(note.isPinned ? 'Unpin' : 'Pin',
                  style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 16, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              const Text('Duplicate', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_rounded, size: 16, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete',
                  style: TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
    if (result == 'pin') {
      widget.appState.togglePin(note);
    } else if (result == 'duplicate') {
      widget.appState.duplicateNote(note);
    } else if (result == 'delete') {
      widget.appState.deleteNote(note.id);
    }
  }

  void _showCreateProjectDialog(Color accentColor, {NoteProject? parent}) {
    final nameController = TextEditingController();
    int selectedColor = accentColor.toARGB32();
    final colorOptions = [
      accentColor.toARGB32(),
      Colors.red.toARGB32(),
      Colors.orange.toARGB32(),
      Colors.green.toARGB32(),
      Colors.blue.toARGB32(),
      Colors.purple.toARGB32(),
      Colors.pink.toARGB32(),
      Colors.teal.toARGB32(),
    ];

    showAnimatedDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(parent == null
              ? 'New Project'
              : 'New Project in "${parent.name}"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Project name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: colorOptions.map((c) {
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedColor = c),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: selectedColor == c
                            ? Border.all(
                                color:
                                    Theme.of(ctx).brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                                width: 2,
                              )
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                await widget.appState.createNoteProject(
                  name: name,
                  colorValue: selectedColor,
                  parentId: parent?.id,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() {});
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showImportDialog(BuildContext context, Color accentColor) {
    final controller = TextEditingController();
    showAnimatedDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import shared note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Paste share link',
            hintText: 'https://...',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) async {
            final url = value.trim();
            if (url.isEmpty) return;
            final title = await widget.appState.importFromShareLink(url);
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted && title != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Imported "$title"'),
                  backgroundColor: accentColor,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            } else if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Failed to import. Link may be expired.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isEmpty) return;
              final title = await widget.appState.importFromShareLink(url);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted && title != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Imported "$title"'),
                    backgroundColor: accentColor,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to import. Link may be expired.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _showProjectContextMenu(Offset position, NoteProject project) async {
    final accentColor = widget.themeState.accentColor;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'new_sub',
          child: Row(
            children: [
              Icon(Icons.create_new_folder_rounded,
                  size: 16, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              const Text('New sub-folder', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: 16, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              const Text('Rename project', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_rounded, size: 16, color: Colors.red),
              SizedBox(width: 8),
              Text(
                'Delete project',
                style: TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
    if (result == 'new_sub') {
      _showCreateProjectDialog(accentColor, parent: project);
    } else if (result == 'rename') {
      _showRenameProjectDialog(project);
    } else if (result == 'delete') {
      _showDeleteProjectDialog(project);
    }
  }

  void _showDeleteProjectDialog(NoteProject project) {
    final noteCount = widget.appState.notes
        .where((n) => n.projectId == project.id)
        .length;

    showAnimatedDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${project.name}"?'),
        content: Text(
          'This will permanently delete the project and all '
          '$noteCount note${noteCount == 1 ? '' : 's'} inside it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await widget.appState.deleteNoteProject(project.id);
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() {});
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showRenameProjectDialog(NoteProject project) {
    final controller = TextEditingController(text: project.name);

    showAnimatedDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Project name',
          ),
          onSubmitted: (value) async {
            final name = value.trim();
            if (name.isNotEmpty && name != project.name) {
              await widget.appState.renameNoteProject(project.id, name);
              setState(() {});
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty && name != project.name) {
                await widget.appState.renameNoteProject(project.id, name);
                setState(() {});
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showUnlockDialog(
    BuildContext context,
    SecurityState securityState,
    String noteId,
    VoidCallback onSuccess,
  ) {
    final pinController = TextEditingController();
    final errorNotifier = ValueNotifier<String?>(null);

    showAnimatedDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlock Note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your PIN to access locked notes.'),
            const SizedBox(height: 12),
            TextField(
              controller: pinController,
              obscureText: true,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Enter PIN'),
              onSubmitted: (value) {
                if (securityState.verifyAndUnlock(noteId, value)) {
                  Navigator.pop(ctx);
                  setState(() {});
                  onSuccess();
                } else {
                  errorNotifier.value = 'Incorrect PIN';
                }
              },
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
            onPressed: () {
              if (securityState.verifyAndUnlock(noteId, pinController.text)) {
                Navigator.pop(ctx);
                setState(() {});
                onSuccess();
              } else {
                errorNotifier.value = 'Incorrect PIN';
              }
            },
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBtn({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white.withValues(alpha: 0.2) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected && !isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 3,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? accentColor
                  : (isDark ? Colors.white54 : Colors.grey.shade400),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? accentColor
                    : (isDark ? Colors.white54 : Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DefaultStyles _buildQuillStyles(ThemeData theme, {Color? noteColor}) {
    final fontSize = widget.themeState.editorFontSize;
    final lh = widget.themeState.editorLineHeight;
    final textColor = noteColor != null ? Colors.white : widget.themeState.editorTextColor;
    final mutedColor = noteColor != null ? Colors.white60 : widget.themeState.editorMutedTextColor;

    return DefaultStyles(
      placeHolder: DefaultTextBlockStyle(
        TextStyle(fontSize: fontSize, height: lh, color: mutedColor),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(4, 4),
        const VerticalSpacing(0, 0),
        null,
      ),
      paragraph: DefaultTextBlockStyle(
        TextStyle(fontSize: fontSize, height: lh, color: textColor),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(4, 4),
        const VerticalSpacing(0, 0),
        null,
      ),
      lists: DefaultListBlockStyle(
        TextStyle(fontSize: fontSize, height: lh, color: textColor),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(4, 4),
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

  Widget _buildEditorPanel(
    BuildContext context,
    ThemeData theme,
    Color accentColor,
  ) {
    final note = widget.appState.currentNote;

    final isDark = theme.brightness == Brightness.dark;
    final chipBorder = widget.themeState.editorBorderColor;

    // Show locked state instead of editor content
    if (note != null && note.isLocked && !GetIt.instance<SecurityState>().isNoteUnlocked(note.id)) {
      return GlassmorphicContainer(
        borderRadius: 20,
        color: widget.themeState.editorBgColor,
        opacity: isDark ? 0.90 : 0.92,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'This note is locked',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your PIN to view',
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.grey.shade500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (note == null || _quillController == null) {
      return GlassmorphicContainer(
        borderRadius: 20,
        color: widget.themeState.editorBgColor,
        opacity: isDark ? 0.90 : 0.92,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.edit_note_rounded,
                size: 56,
                color: isDark ? Colors.white30 : Colors.grey.shade300,
              ),
              const SizedBox(height: 12),
              Text(
                'Select a note to edit',
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.grey.shade400,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final noteColor = _parseNoteColor(note.color);
    final inlineBg = noteColor ?? widget.themeState.editorBgColor;

    return GlassmorphicContainer(
      borderRadius: 20,
      color: inlineBg,
      opacity: noteColor != null ? 0.80 : (isDark ? 0.90 : 0.95),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Title + Open in full editor button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _titleController,
                      onChanged: (_) {
                        _prevTitle = _titleController.text;
                        _onUserEdit();
                      },
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: noteColor != null ? Colors.white : widget.themeState.editorTextColor,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Note title...',
                        filled: true,
                        fillColor: noteColor != null
                            ? Colors.white.withValues(alpha: 0.10)
                            : (widget.themeState.editorBgColor.computeLuminance() >
                                0.5
                            ? Colors.grey.shade50
                            : Colors.white.withValues(alpha: 0.06)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: chipBorder, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: accentColor.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        hintStyle: TextStyle(
                          color: noteColor != null ? Colors.white60 : widget.themeState.editorMutedTextColor,
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Save indicator
                ValueListenableBuilder<String>(
                  valueListenable: _saveStatus,
                  builder: (context, status, _) {
                    return AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      alignment: Alignment.centerLeft,
                      child: status == 'saved'
                          ? Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
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
                                    size: 13,
                                    color: isDark
                                        ? Colors.green.shade300
                                        : Colors.green.shade600,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Saved',
                                    style: TextStyle(
                                      fontSize: 11,
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
                const SizedBox(width: 4),
                // Note color picker
                _buildInlineColorButton(note, accentColor, noteColor),
                const SizedBox(width: 4),
                // Sticky note mode — icon only to save space
                IconButton(
                  onPressed: () => widget.appState.enterCompactMode(note),
                  icon: Icon(
                    Icons.sticky_note_2_outlined,
                    size: 18,
                    color: noteColor != null ? Colors.white : accentColor,
                  ),
                  tooltip: 'Sticky Note',
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                const SizedBox(width: 2),
                // Open in full editor — icon only to save space
                IconButton(
                  onPressed: () => widget.appState.selectNote(note),
                  icon: Icon(
                    Icons.open_in_new_rounded,
                    size: 18,
                    color: noteColor != null ? Colors.white : accentColor,
                  ),
                  tooltip: 'Full Editor',
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          Divider(color: theme.dividerColor.withValues(alpha: 0.1), height: 1),

          // Editable content
          // Listener ensures keyboard focus transfers on any pointer
          // interaction so Cmd+C / Ctrl+C works on the first try
          // (macOS requires explicit focus for shortcuts).
          Expanded(
            child: Listener(
              onPointerDown: (_) {
                if (!_editorFocusNode.hasFocus) {
                  _editorFocusNode.requestFocus();
                }
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent &&
                        event is! KeyRepeatEvent) {
                      return KeyEventResult.ignored;
                    }
                    if (event.logicalKey !=
                        LogicalKeyboardKey.backspace) {
                      return KeyEventResult.ignored;
                    }
                    final ctrl = _quillController!;
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
                    final text = ctrl.document.toPlainText();
                    int lineStart = offset;
                    while (lineStart > 0 &&
                        text[lineStart - 1] != '\n') {
                      lineStart--;
                    }
                    if (offset != lineStart) {
                      return KeyEventResult.ignored;
                    }
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
                    controller: _quillController!,
                    focusNode: _editorFocusNode,
                    config: QuillEditorConfig(
                      placeholder: 'Start writing...',
                      padding: const EdgeInsets.all(8),
                      expands: true,
                      enableAlwaysIndentOnTab: true,
                      textSelectionThemeData: TextSelectionThemeData(
                        cursorColor: accentColor,
                        selectionColor: accentColor.withValues(alpha: 0.3),
                      ),
                      customStyles: _buildQuillStyles(theme, noteColor: noteColor),
                      customLinkPrefixes: const ['notex://'],
                      onLaunchUrl: (url) {
                        if (url.startsWith('notex://')) {
                          final noteId = url.substring('notex://'.length);
                          final target = widget.appState.notes.cast<Note?>().firstWhere(
                                (n) => n?.id == noteId,
                                orElse: () => null,
                              );
                          if (target != null) {
                            widget.appState.selectNote(target);
                          }
                          return;
                        }
                        launchUrl(Uri.parse(url));
                      },
                      linkActionPickerDelegate: (context, link, node) async {
                        if (link.startsWith('notex://')) {
                          final noteId = link.substring('notex://'.length);
                          final target = widget.appState.notes.cast<Note?>().firstWhere(
                                (n) => n?.id == noteId,
                                orElse: () => null,
                              );
                          if (target != null) {
                            widget.appState.selectNote(target);
                          }
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
    );
  }

  // ── Inline note color picker ───────────────────────────────────────────

  Widget _buildInlineColorButton(
    Note note,
    Color accentColor,
    Color? noteColor,
  ) {
    final iconCol = noteColor != null ? Colors.white : accentColor;
    return IconButton(
      onPressed: () => _showInlineColorPicker(note, accentColor),
      icon: noteColor != null
          ? Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: noteColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white54, width: 1.5),
              ),
            )
          : Icon(Icons.palette_outlined, size: 18, color: iconCol),
      tooltip: 'Note Color',
      splashRadius: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  void _showInlineColorPicker(Note note, Color accentColor) {
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Clear / no color
                    _colorSwatch(ctx, note: note, color: null,
                        isSelected: currentColor == null,
                        accentColor: accentColor, isDark: isDark,
                        icon: Icons.block_rounded),
                    ...ThemeState.presetColors.map((c) => _colorSwatch(
                          ctx, note: note, color: c,
                          isSelected: currentColor != null &&
                              currentColor.toARGB32() == c.toARGB32(),
                          accentColor: accentColor, isDark: isDark)),
                  ],
                ),
                const SizedBox(height: 16),
                _customColorSwatch(ctx, note: note,
                    currentColor: currentColor ?? accentColor,
                    accentColor: accentColor, isDark: isDark),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _colorSwatch(BuildContext ctx,
      {required Note note, required Color? color, required bool isSelected,
      required Color accentColor, required bool isDark, IconData? icon}) {
    return InkWell(
      onTap: () {
        final hex = color != null
            ? color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()
            : null;
        widget.appState.updateNoteColor(note, hex);
        Navigator.of(ctx).pop();
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color ?? (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
          border: isSelected
              ? Border.all(color: isDark ? Colors.white : Colors.black87, width: 3)
              : Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.20)
                      : Colors.grey.shade400, width: 1),
          boxShadow: isSelected
              ? [BoxShadow(color: accentColor.withValues(alpha: 0.5),
                    blurRadius: 12, spreadRadius: 2)]
              : null,
        ),
        child: icon != null
            ? Icon(icon, size: 16,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)
            : isSelected
                ? Icon(Icons.check, size: 16,
                    color: (color?.computeLuminance() ?? 0) > 0.5
                        ? Colors.black87 : Colors.white)
                : null,
      ),
    );
  }

  Widget _customColorSwatch(BuildContext ctx,
      {required Note note, required Color currentColor,
      required Color accentColor, required bool isDark}) {
    final isCustom = !ThemeState.presetColors
        .any((c) => c.toARGB32() == currentColor.toARGB32());
    return InkWell(
      onTap: () async {
        Navigator.of(ctx).pop();
        final result = await _showCustomColorPicker(currentColor, accentColor, isDark);
        if (result != null) {
          final hex = result.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
          widget.appState.updateNoteColor(note, hex);
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isCustom ? null : const SweepGradient(colors: [
            Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
            Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ]),
          color: isCustom ? currentColor : null,
          border: isCustom
              ? Border.all(color: isDark ? Colors.white : Colors.black87, width: 3)
              : Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.20)
                      : Colors.grey.shade400, width: 1.5),
        ),
        child: isCustom
            ? Icon(Icons.check, size: 16,
                color: currentColor.computeLuminance() > 0.5
                    ? Colors.black87 : Colors.white)
            : null,
      ),
    );
  }

  Future<Color?> _showCustomColorPicker(
      Color initialColor, Color accentColor, bool isDark) async {
    Color picked = initialColor;
    final bg = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    return showDialog<Color>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Custom Color', style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 16,
                  color: isDark ? Colors.white : Colors.grey.shade800)),
                const SizedBox(height: 20),
                ColorPicker(
                  pickerColor: picked,
                  onColorChanged: (c) => setDialogState(() => picked = c),
                  colorPickerWidth: 300, pickerAreaHeightPercent: 0.7,
                  enableAlpha: false, displayThumbColor: true,
                  hexInputBar: true, labelTypes: const [],
                  pickerAreaBorderRadius:
                      const BorderRadius.all(Radius.circular(12)),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(null),
                      child: Text('Cancel',
                          style: TextStyle(color: Colors.grey.shade500)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: accentColor,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(picked),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color? _parseNoteColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final value = int.tryParse(hex, radix: 16);
    return value != null ? Color(value) : null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Staggered entrance animation for list items.
// Each card fades in and slides up with a small delay based on its index.
// ─────────────────────────────────────────────────────────────────────────────

class _StaggeredEntry extends StatefulWidget {
  final int index;
  final Widget child;
  const _StaggeredEntry({required this.index, required this.child});

  @override
  State<_StaggeredEntry> createState() => _StaggeredEntryState();
}

class _StaggeredEntryState extends State<_StaggeredEntry> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    // Cap stagger at 8 items to avoid slow entrance on large lists.
    final delay = widget.index.clamp(0, 8) * 40;
    Future.delayed(Duration(milliseconds: delay), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _visible ? 0 : 12, 0),
        child: widget.child,
      ),
    );
  }
}

/// A row in the folder tree. Renders indentation, optional chevron,
/// folder color dot/icon, name and note count.
class _FolderTreeRow extends StatefulWidget {
  final String label;
  final int depth;
  // One guide kind per indent column (length == depth). Drives the L-shaped
  // connector lines that visually anchor each row to its parent folder.
  final List<_GuideKind> guides;
  final Color color;
  final bool isDark;
  final bool isSelected;
  final bool hasChildren;
  final bool isExpanded;
  final int count;
  final IconData leadingIcon;
  final VoidCallback onTap;
  final VoidCallback? onChevronTap;
  final VoidCallback? onLongPress;
  // Inline hover actions — when set, small icons appear on the right while
  // the row is hovered so the user can create directly inside this folder
  // without first selecting it.
  final VoidCallback? onCreateNote;
  final VoidCallback? onCreateSubfolder;
  // When true, the trailing action icons are pinned visible instead of only
  // appearing on hover. Used by the root "All" row so users don't need to
  // scroll past a long tree to reach the "+ folder" affordance.
  final bool alwaysShowActions;
  // Drop callback: when set, the row becomes a DragTarget for notes dragged
  // from elsewhere in the tree.
  final void Function(Note note)? onNoteDropped;

  const _FolderTreeRow({
    required this.label,
    required this.depth,
    required this.guides,
    required this.color,
    required this.isDark,
    required this.isSelected,
    required this.hasChildren,
    required this.isExpanded,
    required this.count,
    required this.leadingIcon,
    required this.onTap,
    this.onChevronTap,
    this.onLongPress,
    this.onCreateNote,
    this.onCreateSubfolder,
    this.alwaysShowActions = false,
    this.onNoteDropped,
  });

  @override
  State<_FolderTreeRow> createState() => _FolderTreeRowState();
}

class _FolderTreeRowState extends State<_FolderTreeRow> {
  bool _hover = false;
  bool _isDragOver = false;
  Timer? _autoExpandTimer;

  bool get _isFolderEntry => widget.leadingIcon == Icons.folder_rounded;

  @override
  void dispose() {
    _autoExpandTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedBg = widget.color.withValues(alpha: 0.12);
    final hoverBg = widget.isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.035);
    final textColor = widget.isSelected
        ? widget.color
        : (widget.isDark ? Colors.white70 : Colors.grey.shade700);
    final mutedColor = widget.isDark ? Colors.white38 : Colors.grey.shade500;

    // Swap folder icon based on expanded state; keep custom icons (e.g. the
    // "All" inbox row) untouched.
    final IconData renderIcon = _isFolderEntry
        ? (widget.isExpanded
            ? Icons.folder_open_rounded
            : Icons.folder_rounded)
        : widget.leadingIcon;

    // Folders get a subtle tint of their assigned color so each one has
    // identity even when not selected.
    final iconColor = _isFolderEntry
        ? (widget.isSelected
            ? widget.color
            : widget.color.withValues(alpha: 0.65))
        : (widget.isSelected ? widget.color : mutedColor);

    final dropTintBg = widget.color.withValues(alpha: 0.22);
    final Color rowBg = _isDragOver
        ? dropTintBg
        : (widget.isSelected
            ? selectedBg
            : (_hover ? hoverBg : Colors.transparent));

    final row = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: rowBg,
            border: _isDragOver
                ? Border.all(color: widget.color, width: 1)
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Left accent bar — only visible when selected; gives the row
                // a "snapped to the hierarchy" feel without the heavy full-row
                // fill of the previous design.
                Container(
                  width: 2.5,
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? widget.color
                        : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(6),
                    ),
                  ),
                ),
                // One indent guide per depth level — the last guide draws the
                // L/T bracket that points at this row, the earlier ones draw
                // pass-through verticals only where an ancestor still has
                // siblings below.
                for (final g in widget.guides)
                  _IndentGuide(kind: g, isDark: widget.isDark),
                const SizedBox(width: 4),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: widget.hasChildren
                      ? InkWell(
                          onTap: widget.onChevronTap,
                          borderRadius: BorderRadius.circular(4),
                          child: AnimatedRotation(
                            turns: widget.isExpanded ? 0.25 : 0,
                            duration: const Duration(milliseconds: 150),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: mutedColor,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Icon(renderIcon, size: 14, color: iconColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(
                      widget.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.1,
                        fontWeight: widget.isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                if ((_hover || widget.alwaysShowActions) &&
                    (widget.onCreateNote != null ||
                        widget.onCreateSubfolder != null)) ...[
                  if (widget.onCreateNote != null)
                    _MiniIconButton(
                      icon: Icons.note_add_outlined,
                      tooltip: 'New note here',
                      color: mutedColor,
                      onTap: widget.onCreateNote!,
                    ),
                  if (widget.onCreateSubfolder != null)
                    _MiniIconButton(
                      icon: Icons.create_new_folder_outlined,
                      tooltip: 'New sub-folder',
                      color: mutedColor,
                      onTap: widget.onCreateSubfolder!,
                    ),
                  const SizedBox(width: 4),
                ] else if (widget.count > 0) ...[
                  _CountPill(count: widget.count, isDark: widget.isDark),
                  const SizedBox(width: 6),
                ] else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.onNoteDropped == null) return row;
    return DragTarget<Note>(
      onWillAcceptWithDetails: (details) {
        // Don't visually accept a drop on the note's own folder; the actual
        // no-op write is already short-circuited inside UpdateNoteUseCase,
        // but skipping the highlight avoids misleading affordance.
        return true;
      },
      onMove: (_) {
        if (!_isDragOver) setState(() => _isDragOver = true);
        // Auto-expand a collapsed folder after a brief pause so users can
        // drop into nested folders without first clicking the chevron.
        if (widget.hasChildren &&
            !widget.isExpanded &&
            widget.onChevronTap != null &&
            _autoExpandTimer == null) {
          _autoExpandTimer = Timer(const Duration(milliseconds: 600), () {
            if (mounted && _isDragOver) widget.onChevronTap!();
          });
        }
      },
      onLeave: (_) {
        _autoExpandTimer?.cancel();
        _autoExpandTimer = null;
        if (_isDragOver) setState(() => _isDragOver = false);
      },
      onAcceptWithDetails: (details) {
        _autoExpandTimer?.cancel();
        _autoExpandTimer = null;
        setState(() => _isDragOver = false);
        widget.onNoteDropped!(details.data);
      },
      builder: (_, __, ___) => row,
    );
  }
}

/// A note (leaf) row in the unified tree.
class _NoteTreeRow extends StatefulWidget {
  final Note note;
  final int depth;
  // One guide kind per indent column (length == depth). Mirrors the folder
  // row's tree-bracket scheme so notes nest visually under their folder.
  final List<_GuideKind> guides;
  final bool isDark;
  final Color accentColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _NoteTreeRow({
    required this.note,
    required this.depth,
    required this.guides,
    required this.isDark,
    required this.accentColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_NoteTreeRow> createState() => _NoteTreeRowState();
}

class _NoteTreeRowState extends State<_NoteTreeRow> {
  bool _hover = false;

  String get _displayTitle {
    final t = widget.note.title.trim();
    if (t.isNotEmpty) return t;
    return 'Untitled';
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    final selectedBg = accent.withValues(alpha: 0.12);
    final hoverBg = widget.isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.035);
    final textColor = widget.isSelected
        ? accent
        : (widget.isDark ? Colors.white70 : Colors.grey.shade700);
    final mutedColor = widget.isDark ? Colors.white38 : Colors.grey.shade500;

    final row = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? selectedBg
                : (_hover ? hoverBg : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Left accent bar — only visible when selected.
                Container(
                  width: 2.5,
                  decoration: BoxDecoration(
                    color: widget.isSelected ? accent : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(6),
                    ),
                  ),
                ),
                // Indent guides — notes nest one level deeper than their
                // parent folder; the final guide carries the L/T bracket
                // pointing at this note row.
                for (final g in widget.guides)
                  _IndentGuide(kind: g, isDark: widget.isDark),
                const SizedBox(width: 4),
                // Empty chevron slot to align with folder rows.
                const SizedBox(width: 16),
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Icon(
                    Icons.description_outlined,
                    size: 13,
                    color: widget.isSelected ? accent : mutedColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(
                      _displayTitle,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.1,
                        fontWeight: widget.isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                if (widget.note.isLocked) ...[
                  Icon(Icons.lock_outline_rounded,
                      size: 12, color: mutedColor),
                  const SizedBox(width: 4),
                ],
                if (widget.note.isPinned) ...[
                  Icon(Icons.push_pin_rounded,
                      size: 12,
                      color: widget.isSelected ? accent : mutedColor),
                  const SizedBox(width: 4),
                ],
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );

    final feedback = Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(blurRadius: 10, color: Colors.black38, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined,
                size: 13, color: Colors.white),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                _displayTitle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final placeholder = Opacity(opacity: 0.35, child: row);

    if (kIsMobile) {
      return LongPressDraggable<Note>(
        data: widget.note,
        feedback: feedback,
        childWhenDragging: placeholder,
        child: row,
      );
    }
    return Draggable<Note>(
      data: widget.note,
      feedback: feedback,
      childWhenDragging: placeholder,
      child: row,
    );
  }
}

/// The "+ New folder" row pinned at the bottom of the tree.
class _NewFolderRow extends StatefulWidget {
  final bool isDark;
  final VoidCallback onTap;

  const _NewFolderRow({required this.isDark, required this.onTap});

  @override
  State<_NewFolderRow> createState() => _NewFolderRowState();
}

class _NewFolderRowState extends State<_NewFolderRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isDark
        ? (_hover ? Colors.white70 : Colors.white38)
        : (_hover ? Colors.grey.shade700 : Colors.grey.shade500);
    final hoverBg = widget.isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.035);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(top: 6, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _hover ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.isDark
                  ? Colors.white.withValues(alpha: _hover ? 0.18 : 0.08)
                  : Colors.black.withValues(alpha: _hover ? 0.15 : 0.06),
              width: 1,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.add_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                'New folder',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single vertical guide line drawn in the indent column of a tree row.
/// Multiple guides stack horizontally — one per depth level — to give the
/// tree a clear visual hierarchy like VS Code's explorer.
/// Shape of the indent-guide stroke at one column for one row.
///
/// File-explorer style: pass-through ancestors draw a vertical line; the
/// immediate-parent column of a row draws a tee (├) for non-last children
/// or an ell (└) for the last child of that parent.
enum _GuideKind { none, vertical, tee, ell }

class _IndentGuide extends StatelessWidget {
  final _GuideKind kind;
  final bool isDark;
  const _IndentGuide({required this.kind, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (kind == _GuideKind.none) {
      return const SizedBox(width: 14);
    }
    final color = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);
    return SizedBox(
      width: 14,
      child: CustomPaint(
        painter: _GuidePainter(kind: kind, color: color),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  final _GuideKind kind;
  final Color color;
  _GuidePainter({required this.kind, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    // Vertical trunk x sits slightly left of geometric center so the L's
    // horizontal stroke has visible length pointing toward the chevron.
    const double trunkX = 6.5;
    final double midY = size.height / 2;
    switch (kind) {
      case _GuideKind.none:
        break;
      case _GuideKind.vertical:
        canvas.drawLine(
            const Offset(trunkX, 0), Offset(trunkX, size.height), paint);
        break;
      case _GuideKind.tee:
        canvas.drawLine(
            const Offset(trunkX, 0), Offset(trunkX, size.height), paint);
        canvas.drawLine(
            Offset(trunkX, midY), Offset(size.width, midY), paint);
        break;
      case _GuideKind.ell:
        canvas.drawLine(const Offset(trunkX, 0), Offset(trunkX, midY), paint);
        canvas.drawLine(
            Offset(trunkX, midY), Offset(size.width, midY), paint);
        break;
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      old.kind != kind || old.color != color;
}

/// Pill-shaped badge showing the note count next to a folder name.
class _CountPill extends StatelessWidget {
  final int count;
  final bool isDark;
  const _CountPill({required this.count, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white54 : Colors.grey.shade600,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Tiny icon button used inline on tree rows (e.g. hover-revealed "+ note"
/// and "+ folder" actions on folder rows). Stops the tap from bubbling up
/// to the row's `onTap` so it doesn't also select the folder.
class _MiniIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  State<_MiniIconButton> createState() => _MiniIconButtonState();
}

class _MiniIconButtonState extends State<_MiniIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: _hover
                  ? widget.color.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: 13,
              color: _hover
                  ? widget.color.withValues(alpha: 1.0)
                  : widget.color,
            ),
          ),
        ),
      ),
    );
  }
}
