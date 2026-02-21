import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';

/// Rich text note editor page — full-screen background with overlaid controls.
///
/// Matches the reference design: big background image, glassmorphic inputs on top,
/// and a semi-opaque editor card for readability.
/// NO save button — auto-saves when the user stops typing (800ms debounce).
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

  // Save indicator
  String _saveStatus = ''; // '', 'saving', 'saved'

  @override
  void initState() {
    super.initState();
    _editorFocusNode = FocusNode();
    _titleController = TextEditingController();
    _quillController = QuillController.basic();
    _loadNote();

    // Chain into the save callback to update our indicator
    final originalOnSaved = widget.appState.autoSaveService.onSaved;
    widget.appState.autoSaveService.onSaved = (noteId) async {
      if (originalOnSaved != null) await originalOnSaved(noteId);
      if (mounted) {
        setState(() => _saveStatus = 'saved');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _saveStatus = '');
        });
      }
    };
  }

  void _loadNote() {
    final note = widget.appState.currentNote;
    if (note == null || note.id == _loadedNoteId) return;
    _loadedNoteId = note.id;

    _titleController.text = note.title;

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
    _quillController.document.changes.listen((_) {
      _scheduleAutoSave();
    });
  }

  void _scheduleAutoSave() {
    final note = widget.appState.currentNote;
    if (note == null) return;

    setState(() => _saveStatus = 'saving');

    final content = jsonEncode(_quillController.document.toDelta().toJson());
    widget.appState.autoSaveService.scheduleAutoSave(
      noteId: note.id,
      title: _titleController.text,
      content: content,
    );
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
    // Force-save before leaving
    final note = widget.appState.currentNote;
    if (note != null) {
      final content = jsonEncode(_quillController.document.toDelta().toJson());
      widget.appState.autoSaveService.forceSave(
        noteId: note.id,
        title: _titleController.text,
        content: content,
      );
    }

    _quillController.dispose();
    _titleController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = widget.themeState.accentColor;
    final note = widget.appState.currentNote;

    if (note == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.note_add_rounded,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No note selected',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.grey.shade400,
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // Top controls row: title + toolbar
          Row(
            children: [
              // Title input — styled like search bar
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    controller: _titleController,
                    onChanged: (_) => _scheduleAutoSave(),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Colors.grey.shade800,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Note title...',
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.85),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.grey.shade200,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: accentColor.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      prefixIcon: Icon(
                        Icons.edit_note_rounded,
                        color: accentColor.withValues(alpha: 0.6),
                        size: 20,
                      ),
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Date chip
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.grey.shade200,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: accentColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${note.updatedAt.month}/${note.updatedAt.day}/${note.updatedAt.year}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Sync status indicator
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.grey.shade200,
                    width: 1,
                  ),
                ),
                child: Icon(
                  _getSyncIcon(note.syncStatus.name),
                  size: 18,
                  color: accentColor,
                ),
              ),

              // Save indicator
              AnimatedOpacity(
                opacity: _saveStatus.isNotEmpty ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  height: 44,
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _saveStatus == 'saved'
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _saveStatus == 'saved'
                          ? Colors.green.shade200
                          : Colors.orange.shade200,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _saveStatus == 'saved'
                            ? Icons.check_circle_outline_rounded
                            : Icons.sync_rounded,
                        size: 14,
                        color: _saveStatus == 'saved'
                            ? Colors.green.shade600
                            : Colors.orange.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _saveStatus == 'saved' ? 'Saved' : 'Saving...',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _saveStatus == 'saved'
                              ? Colors.green.shade600
                              : Colors.orange.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Main editor area — split into toolbar and editor body
          Expanded(
            child: Row(
              children: [
                // Editor body with toolbar on top
                Expanded(
                  child: Column(
                    children: [
                      // Quill toolbar — white card
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                          border: Border.all(
                            color: Colors.grey.shade200,
                            width: 1,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: QuillSimpleToolbar(
                          controller: _quillController,
                          config: QuillSimpleToolbarConfig(
                            showAlignmentButtons: true,
                            showBackgroundColorButton: false,
                            showClearFormat: false,
                            showFontFamily: false,
                            showFontSize: false,
                            showInlineCode: true,
                            showCodeBlock: true,
                            showListCheck: true,
                            multiRowsDisplay: false,
                            decoration: const BoxDecoration(),
                            buttonOptions: QuillSimpleToolbarButtonOptions(
                              base: QuillToolbarBaseButtonOptions(
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

                      // Editor content — solid white card for readability
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 1),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(20),
                              bottomRight: Radius.circular(20),
                            ),
                            border: Border(
                              left: BorderSide(
                                color: Colors.grey.shade200,
                                width: 1,
                              ),
                              right: BorderSide(
                                color: Colors.grey.shade200,
                                width: 1,
                              ),
                              bottom: BorderSide(
                                color: Colors.grey.shade200,
                                width: 1,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(24),
                          child: QuillEditor.basic(
                            controller: _quillController,
                            focusNode: _editorFocusNode,
                            config: QuillEditorConfig(
                              placeholder: 'Start writing your thoughts...',
                              padding: const EdgeInsets.all(8),
                              expands: true,
                              customStyles: DefaultStyles(
                                paragraph: DefaultTextBlockStyle(
                                  TextStyle(
                                    fontSize: 15,
                                    height: 1.6,
                                    color: Colors.grey.shade800,
                                  ),
                                  const HorizontalSpacing(0, 0),
                                  const VerticalSpacing(6, 6),
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
              ],
            ),
          ),
        ],
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
}
