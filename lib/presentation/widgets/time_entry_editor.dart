import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../domain/entities/project.dart';
import '../../domain/entities/time_entry.dart';

/// The result of editing an entry, or null when the dialog was dismissed.
class TimeEntryEdit {
  const TimeEntryEdit({
    required this.description,
    required this.projectId,
    required this.startTime,
    required this.endTime,
  });

  final String description;
  final String? projectId;
  final DateTime startTime;

  /// Null while the entry is still running; a running entry has no end to set.
  final DateTime? endTime;
}

/// Edits a tracked entry: what it was, which project it belonged to, and when
/// it actually happened.
///
/// A tracker that cannot be corrected is a tracker people stop trusting — the
/// timer is always started late or stopped after the fact, and an entry nobody
/// can fix is an entry nobody believes. Everything here was already supported
/// by the update use case; only the way in was missing.
class TimeEntryEditor extends StatefulWidget {
  const TimeEntryEditor({
    super.key,
    required this.entry,
    required this.projects,
    required this.accentColor,
    required this.surfaceColor,
    required this.textColor,
  });

  final TimeEntry entry;
  final List<Project> projects;
  final Color accentColor;
  final Color surfaceColor;
  final Color textColor;

  @override
  State<TimeEntryEditor> createState() => _TimeEntryEditorState();
}

class _TimeEntryEditorState extends State<TimeEntryEditor> {
  late final TextEditingController _description = TextEditingController(
    text: widget.entry.description,
  );

  late String? _projectId = widget.entry.projectId;
  late DateTime _start = widget.entry.startTime;
  late DateTime? _end = widget.entry.endTime;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Duration get _duration =>
      (_end ?? DateTime.now()).difference(_start).isNegative
      ? Duration.zero
      : (_end ?? DateTime.now()).difference(_start);

  String get _durationLabel {
    final d = _duration;
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _pickStart() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (time == null) return;

    setState(() {
      _start = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );

      // Moving the start past the end would invert the entry. The end follows
      // it rather than the edit being rejected: the user is fixing a start
      // time, not asking to be told they got it wrong.
      final end = _end;
      if (end != null && end.isBefore(_start)) {
        _end = _start.add(const Duration(minutes: 1));
      }
    });
  }

  Future<void> _pickEnd() async {
    final end = _end;
    if (end == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(end),
    );
    if (time == null) return;

    setState(() {
      var candidate = DateTime(
        _start.year,
        _start.month,
        _start.day,
        time.hour,
        time.minute,
      );

      // An end before the start is the ordinary case of a session that ran
      // past midnight, not a mistake, so it rolls to the next day rather than
      // being refused.
      if (candidate.isBefore(_start)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      _end = candidate;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.surfaceColor.computeLuminance() < 0.5;
    final muted = widget.textColor.withValues(alpha: 0.6);

    return AlertDialog(
      backgroundColor: Color.alphaBlend(
        widget.surfaceColor.withValues(alpha: 0.96),
        isDark ? Colors.black : Colors.white,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Edit entry', style: TextStyle(color: widget.textColor)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _description,
              autofocus: true,
              style: TextStyle(color: widget.textColor),
              decoration: InputDecoration(
                labelText: 'Description',
                labelStyle: TextStyle(color: muted),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: widget.accentColor),
                ),
              ),
            ),
            const SizedBox(height: 18),

            DropdownButtonFormField<String?>(
              initialValue: _projectId,
              isExpanded: true,
              dropdownColor: Color.alphaBlend(
                widget.surfaceColor.withValues(alpha: 0.98),
                isDark ? Colors.black : Colors.white,
              ),
              style: TextStyle(color: widget.textColor),
              decoration: InputDecoration(
                labelText: 'Project',
                labelStyle: TextStyle(color: muted),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('No Project', style: TextStyle(color: muted)),
                ),
                ...widget.projects.map(
                  (project) => DropdownMenuItem<String?>(
                    value: project.id,
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Color(project.colorValue),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            project.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: widget.textColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _projectId = value),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: _TimeField(
                    label: 'Start',
                    value: _formatDateTime(_start),
                    textColor: widget.textColor,
                    mutedColor: muted,
                    accentColor: widget.accentColor,
                    onTap: _pickStart,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimeField(
                    label: 'End',
                    // A running entry has no end, and offering to set one
                    // would be offering to stop it from a dialog that is not
                    // about stopping it.
                    value: _end == null ? 'Running' : _formatDateTime(_end!),
                    textColor: widget.textColor,
                    mutedColor: muted,
                    accentColor: widget.accentColor,
                    onTap: _end == null ? null : _pickEnd,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // The number the edit is really about: times are how you say it,
            // duration is what you meant.
            Row(
              children: [
                Text('Duration', style: TextStyle(color: muted, fontSize: 13)),
                const Spacer(),
                Text(
                  _durationLabel,
                  style: TextStyle(
                    color: widget.accentColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: muted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: widget.accentColor,
            // The label has to be read against whatever accent the user chose.
            // Left to the ambient theme it inherits a colour picked for some
            // other surface, and a pale accent ends up carrying dark red text.
            foregroundColor: widget.accentColor.computeLuminance() > 0.5
                ? Colors.black
                : Colors.white,
          ),
          onPressed: () => Navigator.pop(
            context,
            TimeEntryEdit(
              description: _description.text.trim(),
              projectId: _projectId,
              startTime: _start,
              endTime: _end,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final today = DateTime.now();
    final sameDay =
        value.year == today.year &&
        value.month == today.month &&
        value.day == today.day;

    final time =
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

    // The date is dropped when it is today's, which is most entries. Repeating
    // it on every row is noise that hides the one entry where it matters.
    return sameDay ? time : '${months[value.month - 1]} ${value.day} · $time';
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.textColor,
    required this.mutedColor,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color textColor;
  final Color mutedColor;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: mutedColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: mutedColor, fontSize: 11)),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                color: enabled ? textColor : mutedColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
