import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../widgets/note_card.dart';
import '../widgets/glassmorphic_container.dart';

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

  @override
  void dispose() {
    _forceSave();
    _quillController?.dispose();
    _titleController?.dispose();
    _quillScrollController.dispose();
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
              opacity: theme.brightness == Brightness.dark ? 0.3 : 0.92,
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

                  const SizedBox(height: 12),

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
                            itemCount: displayedNotes.length,
                            itemBuilder: (context, index) {
                              final note = displayedNotes[index];
                              return NoteCard(
                                note: note,
                                isSelected: note.id ==
                                    widget.appState.currentNote?.id,
                                accentColor: accentColor,
                                onTap: () {
                                  widget.appState.previewNote(note);
                                  setState(() => _loadPreview());
                                },
                                onPin: () => widget.appState.togglePin(note),
                                onDelete: () =>
                                    widget.appState.deleteNote(note.id),
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

  Widget _buildEditorPanel(
      BuildContext context, ThemeData theme, Color accentColor) {
    final note = widget.appState.currentNote;

    if (note == null || _quillController == null) {
      return GlassmorphicContainer(
        borderRadius: 20,
        opacity: theme.brightness == Brightness.dark ? 0.3 : 0.92,
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
      opacity: theme.brightness == Brightness.dark ? 0.3 : 0.95,
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
                focusNode: FocusNode(),
                scrollController: _quillScrollController,
                config: QuillEditorConfig(
                  placeholder: 'Start typing...',
                  padding: EdgeInsets.zero,
                  expands: true,
                  customStyles: DefaultStyles(
                    paragraph: DefaultTextBlockStyle(
                      TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: theme.brightness == Brightness.dark
                            ? Colors.white
                            : Colors.grey.shade800,
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
    );
  }
}
