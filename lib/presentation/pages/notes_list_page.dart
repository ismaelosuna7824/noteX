import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../../domain/entities/note_project.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../widgets/note_card.dart';
import '../widgets/glassmorphic_container.dart';
import '../widgets/animated_dialog.dart';

/// Notes list view with inline preview/edit panel.
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
  TextEditingController? _titleController;
  String? _loadedNoteId;

  /// Persistent scroll controller for the Quill editor.
  /// Created once so the platform scrollbar always has a valid position.
  final ScrollController _quillScrollController = ScrollController();

  /// Persistent focus node for the Quill editor.
  /// Creating a new FocusNode on every build causes the cursor to disappear.
  final FocusNode _editorFocusNode = FocusNode();

  @override
  void dispose() {
    _forceSave();
    _quillController?.dispose();
    _titleController?.dispose();
    _quillScrollController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  void _loadPreview() {
    final note = widget.appState.currentNote;
    if (note == null || note.id == _loadedNoteId) return;

    _forceSave(); // save previous note before switching
    _loadedNoteId = note.id;

    _titleController?.dispose();
    _titleController = TextEditingController(text: note.title);

    _quillController?.dispose();
    try {
      final delta = Document.fromJson(jsonDecode(note.content));
      _quillController = QuillController(
        document: delta,
        selection: const TextSelection.collapsed(offset: 0),
      );
    } catch (_) {
      _quillController = QuillController.basic();
    }

    // Listen for content changes → auto-save
    _quillController!.document.changes.listen((_) {
      _scheduleAutoSave();
    });
  }

  void _scheduleAutoSave() {
    // Use _loadedNoteId — the note currently loaded in the editor.
    // currentNote may already point to a newly selected note during a switch.
    final noteId = _loadedNoteId;
    if (noteId == null || _quillController == null) return;

    final content =
        jsonEncode(_quillController!.document.toDelta().toJson());
    widget.appState.autoSaveService.scheduleAutoSave(
      noteId: noteId,
      title: _titleController?.text ?? '',
      content: content,
    );
  }

  void _forceSave() {
    // IMPORTANT: use _loadedNoteId, NOT currentNote.id.
    // When switching notes, previewNote() updates currentNote to the NEW note
    // before _forceSave() runs, so using currentNote.id would save the OLD
    // editor content into the NEW note — overwriting its title/content.
    final noteId = _loadedNoteId;
    if (noteId == null || _quillController == null) return;

    final content =
        jsonEncode(_quillController!.document.toDelta().toJson());
    widget.appState.autoSaveService.forceSave(
      noteId: noteId,
      title: _titleController?.text ?? '',
      content: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = widget.themeState.accentColor;

    // Reload preview if note changed
    if (widget.appState.currentNote?.id != _loadedNoteId) {
      _loadPreview();
    }

    final showPinned = widget.appState.showPinnedTab;
    final displayedNotes =
        showPinned ? widget.appState.pinnedNotes : widget.appState.filteredNotes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          // Notes list panel
          SizedBox(
            width: 320,
            child: GlassmorphicContainer(
              borderRadius: 20,
              opacity: theme.brightness == Brightness.dark ? 0.90 : 0.92,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Header
                  Row(
                    children: [
                      Text(
                        'My Notes',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
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
                              label: 'All',
                              isSelected: !showPinned,
                              accentColor: accentColor,
                              onTap: () =>
                                  widget.appState.setShowPinnedTab(false),
                            ),
                            _buildTabBtn(
                              icon: Icons.push_pin_rounded,
                              label: 'Pinned',
                              isSelected: showPinned,
                              accentColor: accentColor,
                              onTap: () =>
                                  widget.appState.setShowPinnedTab(true),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
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
                          child: const Icon(Icons.add,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Project filter chips (always visible so user can create first project)
                  _buildProjectChips(theme, accentColor),
                  const SizedBox(height: 8),

                  // Notes list
                  Expanded(
                    child: displayedNotes.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  showPinned
                                      ? Icons.push_pin_outlined
                                      : Icons.note_alt_outlined,
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
                          )
                        : ListView.builder(
                            key: ValueKey(showPinned ? 'pinned' : 'all'),
                            itemCount: displayedNotes.length,
                            itemBuilder: (context, index) {
                              final note = displayedNotes[index];
                              return _StaggeredEntry(
                                index: index,
                                child: NoteCard(
                                  note: note,
                                  isSelected: note.id ==
                                      widget.appState.currentNote?.id,
                                  accentColor: accentColor,
                                  onTap: () {
                                    widget.appState.previewNote(note);
                                    setState(() => _loadPreview());
                                  },
                                  onPin: () =>
                                      widget.appState.togglePin(note),
                                  onDelete: () =>
                                      widget.appState.deleteNote(note.id),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Preview/edit panel
          Expanded(
            child: _buildEditorPanel(context, theme, accentColor),
          ),
        ],
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
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
          },
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
                child: Icon(Icons.add, size: 14,
                    color: isDark ? Colors.white54 : Colors.grey.shade500),
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
                                color: Theme.of(ctx).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                                width: 2)
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

  void _showProjectContextMenu(
      Offset position, NoteProject project) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_rounded, size: 16, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete project',
                  style: TextStyle(color: Colors.red, fontSize: 13)),
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
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
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

  DefaultStyles _buildQuillStyles(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
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
        const VerticalSpacing(4, 4),
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
        const VerticalSpacing(4, 4),
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
        const VerticalSpacing(4, 4),
        const VerticalSpacing(0, 0),
        null,
        null,
      ),
    );
  }

  Widget _buildEditorPanel(
      BuildContext context, ThemeData theme, Color accentColor) {
    final note = widget.appState.currentNote;

    if (note == null || _quillController == null) {
      return GlassmorphicContainer(
        borderRadius: 20,
        opacity: theme.brightness == Brightness.dark ? 0.90 : 0.92,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.edit_note_rounded,
                  size: 56,
                  color: theme.brightness == Brightness.dark
                      ? Colors.white30
                      : Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                'Select a note to preview',
                style: TextStyle(
                  color: theme.brightness == Brightness.dark
                      ? Colors.white54
                      : Colors.grey.shade400,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GlassmorphicContainer(
      borderRadius: 20,
      opacity: theme.brightness == Brightness.dark ? 0.90 : 0.95,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Title + Open in editor button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
            child: Row(
              children: [
                // Inline title field
                Expanded(
                  child: TextField(
                    controller: _titleController,
                    onChanged: (_) => _scheduleAutoSave(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Note title...',
                      border: InputBorder.none,
                      hintStyle: TextStyle(
                        color: theme.brightness == Brightness.dark
                            ? Colors.white54
                            : Colors.grey.shade400,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Date
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time_rounded,
                          size: 12,
                          color: theme.brightness == Brightness.dark
                              ? Colors.white54
                              : Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(
                        '${note.updatedAt.month}/${note.updatedAt.day}',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.brightness == Brightness.dark
                                ? Colors.white54
                                : Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Open in full editor
                InkWell(
                  onTap: () => widget.appState.selectNote(note),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new_rounded,
                            size: 14, color: accentColor),
                        const SizedBox(width: 4),
                        Text(
                          'Open Editor',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          Divider(color: theme.dividerColor.withValues(alpha: 0.1), height: 1),

          // Compact toolbar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: QuillSimpleToolbar(
              controller: _quillController!,
              config: QuillSimpleToolbarConfig(
                showAlignmentButtons: false,
                showBackgroundColorButton: false,
                showClearFormat: false,
                showCodeBlock: false,
                showDirection: false,
                showFontFamily: false,
                showFontSize: false,
                showHeaderStyle: true,
                showIndent: false,
                showInlineCode: false,
                showLink: false,
                showQuote: false,
                showSearchButton: false,
                showStrikeThrough: false,
                showSubscript: false,
                showSuperscript: false,
                showUndo: false,
                showRedo: false,
                showColorButton: false,
                showListCheck: true,
                multiRowsDisplay: false,
                buttonOptions: QuillSimpleToolbarButtonOptions(
                  base: QuillToolbarBaseButtonOptions(
                    iconSize: 18,
                    iconTheme: QuillIconTheme(
                      iconButtonSelectedData: IconButtonData(
                        color: accentColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          Divider(color: theme.dividerColor.withValues(alpha: 0.1), height: 1),

          // Editor content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: QuillEditor(
                controller: _quillController!,
                focusNode: _editorFocusNode,
                scrollController: _quillScrollController,
                config: QuillEditorConfig(
                  placeholder: 'Start typing...',
                  padding: EdgeInsets.zero,
                  expands: true,
                  textSelectionThemeData: TextSelectionThemeData(
                    cursorColor: theme.brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                  customStyles: _buildQuillStyles(theme),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
