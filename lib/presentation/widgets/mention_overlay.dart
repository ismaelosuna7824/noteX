import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/note.dart';

/// Floating autocomplete overlay for @mention note linking.
///
/// Shows a filtered list of notes matching the query typed after `@`.
/// Supports keyboard navigation (arrow keys + Enter) and mouse selection.
class MentionOverlay extends StatefulWidget {
  final List<Note> notes;
  final String query;
  final ValueChanged<Note> onSelect;
  final VoidCallback onDismiss;
  final Color accentColor;
  final Color bgColor;
  final Color borderColor;
  final Color textColor;
  final Color mutedColor;

  const MentionOverlay({
    super.key,
    required this.notes,
    required this.query,
    required this.onSelect,
    required this.onDismiss,
    required this.accentColor,
    required this.bgColor,
    required this.borderColor,
    required this.textColor,
    required this.mutedColor,
  });

  @override
  State<MentionOverlay> createState() => MentionOverlayState();
}

class MentionOverlayState extends State<MentionOverlay> {
  int _selectedIndex = 0;
  late List<Note> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = _filterNotes();
  }

  @override
  void didUpdateWidget(MentionOverlay old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query || old.notes != widget.notes) {
      _filtered = _filterNotes();
      _selectedIndex = _selectedIndex.clamp(0, (_filtered.length - 1).clamp(0, 999));
    }
  }

  List<Note> _filterNotes() {
    if (widget.query.isEmpty) {
      return widget.notes.take(8).toList();
    }
    final q = widget.query.toLowerCase();
    return widget.notes
        .where((n) => n.title.toLowerCase().contains(q))
        .take(8)
        .toList();
  }

  /// Handle keyboard events from the editor. Returns true if consumed.
  bool handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, _filtered.length - 1);
      });
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, _filtered.length - 1);
      });
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      if (_filtered.isNotEmpty) {
        widget.onSelect(_filtered[_selectedIndex]);
      }
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_filtered.isEmpty) {
      return Material(
        color: widget.bgColor,
        borderRadius: BorderRadius.circular(12),
        elevation: 8,
        child: Container(
          width: 280,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.borderColor, width: 1),
          ),
          child: Text(
            'No notes found',
            style: TextStyle(color: widget.mutedColor, fontSize: 13),
          ),
        ),
      );
    }

    return Material(
      color: widget.bgColor,
      borderRadius: BorderRadius.circular(12),
      elevation: 8,
      child: Container(
        width: 280,
        constraints: const BoxConstraints(maxHeight: 320),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.borderColor, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: _filtered.length,
            itemBuilder: (context, index) {
              final note = _filtered[index];
              final isSelected = index == _selectedIndex;
              return InkWell(
                onTap: () => widget.onSelect(note),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  color: isSelected
                      ? widget.accentColor.withValues(alpha: 0.15)
                      : null,
                  child: Row(
                    children: [
                      Icon(
                        Icons.note_outlined,
                        size: 16,
                        color: isSelected
                            ? widget.accentColor
                            : widget.mutedColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          note.title.isEmpty ? 'Untitled' : note.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: widget.textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
