import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/note.dart';
import '../../domain/services/mention_trigger.dart';
import 'mention_overlay.dart';
import 'note_markdown_editor.dart';

/// Adds the `@mention` note picker to any surface hosting a
/// [NoteMarkdownEditor].
///
/// The editor deliberately knows nothing about notes — it only reports the
/// token under the caret. That leaves every hosting surface needing the same
/// state, the same key routing and the same commit path, so it lives here once
/// instead of three times.
///
/// A host wires it in four steps:
///   1. `with MentionPickerHost`
///   2. pass `onMentionQuery: onMentionQuery` to the editor
///   3. give the editor a [GlobalObjectKey] and return it from [mentionEditorKey]
///   4. render [buildMentionOverlay] above the editor, typically in a [Stack]
mixin MentionPickerHost<T extends StatefulWidget> on State<T> {
  MentionQuery? _query;
  final GlobalKey<MentionOverlayState> _overlayKey = GlobalKey();

  /// The token being composed, or null when no picker is open. Hosts read this
  /// to decide whether to render the overlay at all.
  MentionQuery? get mentionQuery => _query;

  /// Key of the editor the picker should commit into.
  ///
  /// Must be the same [GlobalObjectKey] the host gave its [NoteMarkdownEditor],
  /// which is how the picker reaches [NoteMarkdownEditorState.commitMention].
  GlobalObjectKey<NoteMarkdownEditorState>? get mentionEditorKey;

  @override
  void initState() {
    super.initState();
    // Arrow and Enter keys must beat the TextField to the event. A Focus
    // ancestor never would — EditableText consumes them before they bubble —
    // so this rides the same process-wide handler the editor uses for
    // Cmd/Ctrl+E. It returns false whenever no picker is open, leaving every
    // other keystroke untouched.
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (_query == null) return false;
    return _overlayKey.currentState?.handleKey(event) ?? false;
  }

  /// Pass this to the editor's `onMentionQuery`.
  ///
  /// Rebuilds only when the token actually changes, so typing outside a
  /// mention costs nothing.
  void onMentionQuery(MentionQuery? query) {
    if (query == _query) return;
    setState(() => _query = query);
  }

  /// Closes the picker without inserting anything.
  void closeMentionPicker() {
    if (_query != null) setState(() => _query = null);
  }

  /// Notes offerable while editing [currentNoteId], newest first.
  ///
  /// Excludes the note being edited — a note linking to itself is not a link —
  /// and anything in the trash. Query filtering belongs to the overlay.
  List<Note> mentionCandidates(List<Note> all, String currentNoteId) {
    final candidates = all
        .where((n) => n.id != currentNoteId && n.deletedAt == null)
        .toList();
    candidates.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return candidates;
  }

  /// Replaces the composing token with a Markdown link to [note].
  void commitMention(Note note) {
    final trigger = _query;
    if (trigger == null) return;

    final editorState = mentionEditorKey?.currentState;
    closeMentionPicker();

    editorState?.commitMention(
      trigger: trigger,
      noteId: note.id,
      displayText: note.title,
    );
  }

  /// The floating picker, or an empty box when no mention is open.
  ///
  /// Returns a zero-size widget rather than null so hosts can drop it into a
  /// [Stack] unconditionally.
  Widget buildMentionOverlay({
    required List<Note> notes,
    required String currentNoteId,
    required Color accentColor,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
    required Color mutedColor,
  }) {
    final query = _query;
    if (query == null) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      bottom: 0,
      child: MentionOverlay(
        key: _overlayKey,
        notes: mentionCandidates(notes, currentNoteId),
        query: query.query,
        onSelect: commitMention,
        onDismiss: closeMentionPicker,
        accentColor: accentColor,
        bgColor: bgColor,
        borderColor: borderColor,
        textColor: textColor,
        mutedColor: mutedColor,
      ),
    );
  }
}
