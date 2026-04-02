import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;
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
import '../utils/platform_utils.dart';
import '../widgets/animated_dialog.dart';
import '../widgets/glassmorphic_container.dart';
import '../widgets/note_card.dart';
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
    final listPanel = GlassmorphicContainer(
      borderRadius: 20,
      color: widget.themeState.editorBgColor,
      opacity: theme.brightness == Brightness.dark ? 0.90 : 0.92,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildHeader(theme, accentColor, showPinned),
          const SizedBox(height: 8),
          _buildProjectChips(theme, accentColor),
          const SizedBox(height: 8),
          Expanded(
            child: displayedNotes.isEmpty
                ? _buildEmptyState(theme, showPinned)
                : ListView.builder(
                    key: ValueKey(showPinned ? 'pinned' : 'all'),
                    itemCount: displayedNotes.length,
                    itemBuilder: (context, index) {
                      final note = displayedNotes[index];
                      return _StaggeredEntry(
                        index: index,
                        child: NoteCard(
                          note: note,
                          isSelected:
                              note.id ==
                              widget.appState.currentNote?.id,
                          accentColor: accentColor,
                          editorBgColor:
                              widget.themeState.editorBgColor,
                          onTap: () {
                            widget.appState.previewNote(note);
                            if (kIsMobile) {
                              // Navigate to full-screen editor on mobile
                              widget.appState.navigateToPage(2);
                            } else {
                              setState(() => _loadNote());
                            }
                          },
                          onCompactMode: kIsMobile
                              ? null
                              : () => widget.appState.enterCompactMode(note),
                          onPin: () => widget.appState.togglePin(note),
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
                  ),
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
            _buildProjectChips(theme, accentColor),
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
                                onTap: () {
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

  Widget _buildProjectChips(ThemeData theme, Color accentColor) {
    final isDark = theme.brightness == Brightness.dark;
    final selected = widget.appState.selectedNoteProjectId;
    final projects = widget.appState.noteProjects;

    return SizedBox(
      height: 30,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            // "All" chip
            _buildChip(
              label: 'All',
              isSelected: selected == null,
              color: accentColor,
              isDark: isDark,
              onTap: () => widget.appState.filterByNoteProject(null),
            ),
            const SizedBox(width: 6),
            // Per-project chips
            for (final p in projects) ...[
              GestureDetector(
                onSecondaryTapUp: (details) =>
                    _showProjectContextMenu(details.globalPosition, p),
                child: _buildChip(
                  label: p.name,
                  isSelected: selected == p.id,
                  color: p.color,
                  isDark: isDark,
                  onTap: () => widget.appState.filterByNoteProject(p.id),
                  onLongPress: () => _showDeleteProjectDialog(p),
                ),
              ),
              const SizedBox(width: 6),
            ],
            // "Uncategorized" chip
            _buildChip(
              label: 'Uncategorized',
              isSelected: selected == '__root__',
              color: isDark ? Colors.white54 : Colors.grey,
              isDark: isDark,
              onTap: () => widget.appState.filterByNoteProject('__root__'),
            ),
            const SizedBox(width: 6),
            // "+" button to create project
            InkWell(
              onTap: () => _showCreateProjectDialog(accentColor),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.add,
                  size: 14,
                  color: isDark ? Colors.white54 : Colors.grey.shade500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required bool isSelected,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(14),
          border: isSelected
              ? Border.all(color: color.withValues(alpha: 0.5), width: 1)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? color
                : (isDark ? Colors.white54 : Colors.grey.shade600),
          ),
        ),
      ),
    );
  }

  void _showCreateProjectDialog(Color accentColor) {
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
          title: const Text('New Project'),
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
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
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
    if (result == 'delete') {
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
