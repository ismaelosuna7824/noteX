import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A [TextEditingController] that leaves a fading accent wash behind text the
/// moment it is written, then lets it dry.
///
/// The effect exists to answer a question the caret alone cannot: *what did I
/// just change?* A caret marks where you are; the wash marks where you have
/// been in the last second or so. On a long note that difference matters —
/// after a paste, a toolbar insert, or a mention completion, the caret has
/// already moved on and the edit itself is indistinguishable from text written
/// an hour ago.
///
/// ## Why this is not a per-frame animation
///
/// The obvious implementation — repaint every frame and interpolate the alpha
/// smoothly — makes the whole editor feel heavy, and the reason is specific.
/// [RenderEditable.text] calls `markNeedsLayout()` unconditionally: unlike
/// [RenderParagraph], it does not check whether the new span differs only in
/// paint properties. So handing the field a new [TextSpan] tree re-measures
/// the *entire document*, and a smooth 60fps fade means 60 full text layouts
/// per second for 1.2s after every keystroke, on a note that may be thousands
/// of characters long. Typing normally costs one layout per key; that version
/// cost seventy.
///
/// Two mechanisms keep it cheap instead:
///
/// * **Quantised alpha.** The fade is cut into [_steps] discrete levels. Spans
///   whose values did not change compare equal, and [RenderEditable] early-outs
///   on `_textPainter.text == value` before it ever marks needs-layout. So a
///   1.2s fade costs about a dozen layouts rather than seventy.
/// * **Silent frames.** The ticker still runs at 60fps, but [ink] is only
///   bumped when the quantised picture actually changed. Frames that would
///   rebuild to an identical result never reach the widget tree at all.
///
/// Repaints are driven by [ink], NOT by [notifyListeners]. Notifying the text
/// controller would wake every listener the field has — in a split editor that
/// drags the Markdown preview through the fade too, for a change it cannot
/// even render. Wrap only the field:
///
/// ```dart
/// ListenableBuilder(
///   listenable: controller.ink,
///   builder: (context, _) => TextField(controller: controller, ...),
/// )
/// ```
class TypingInkController extends TextEditingController {
  TypingInkController({
    super.text,
    this.fade = const Duration(milliseconds: 1100),
    this.strength = 0.45,
    this.color,
  });

  /// How long a stretch of new text keeps any wash at all, hold included.
  final Duration fade;

  /// Peak alpha of the wash, held for [_hold] of its life before it starts to
  /// go. Strong enough to read as a deliberate mark rather than a smudge, and
  /// still under half so the body copy underneath stays legible.
  final double strength;

  /// Wash colour. Null resolves to the scheme primary, which the app seeds
  /// from the user's accent — so the ink follows the theme without this
  /// controller having to know the theme exists.
  final Color? color;

  /// Ticks when the quantised wash changes. Nothing else changes, so only the
  /// field needs to listen.
  final ValueNotifier<int> ink = ValueNotifier<int>(0);

  /// Fraction of a mark's life spent at full [strength] before the fade
  /// begins. Without a hold, the wash starts dying the instant it appears and
  /// fast typing never shows it at full — which is exactly why the first cut
  /// of this looked so much weaker than the reference.
  static const double _hold = 0.3;

  /// Discrete alpha levels in the fade. This is the whole performance budget:
  /// each level costs at most one document relayout. Twelve is smooth enough
  /// that the steps are invisible at these durations.
  static const int _steps = 12;

  /// Insertions closer together than this are appended to the previous mark
  /// instead of starting a new one. It bounds the mark count during fast
  /// typing while leaving deliberate typing its per-keystroke gradient.
  static const int _coalesceMs = 90;

  final List<_InkMark> _marks = <_InkMark>[];

  /// Milliseconds accumulated by every ticker run that has already ended.
  ///
  /// The clock is the [Ticker]'s own elapsed time, not a [Stopwatch], and that
  /// is not a detail. A wall clock disagrees with the framework's clock
  /// wherever time is driven rather than observed — most sharply under
  /// `pumpAndSettle`, which advances Flutter's clock while the wall barely
  /// moves, so wall-clock marks never expire and the ticker spins forever.
  /// Each run restarts its elapsed at zero, so finished runs are banked here
  /// and [_now] adds the run in progress.
  int _baseMs = 0;

  /// Elapsed milliseconds inside the current ticker run.
  int _tickMs = 0;

  int get _now => _baseMs + _tickMs;

  Ticker? _ticker;
  bool _disposed = false;

  /// Signature of the last picture actually published through [ink], so an
  /// unchanged frame can be dropped before it costs a rebuild.
  int _published = 0;

  /// Seeding the controller's text through the constructor bypasses this
  /// setter, so opening a note never washes the whole document. Only genuine
  /// mutations — typing, toolbar inserts, mention completion — pass through.
  @override
  set value(TextEditingValue newValue) {
    final String before = super.value.text;
    final String after = newValue.text;
    if (before != after) _record(before, after);
    super.value = newValue;
  }

  /// Diffs [before] against [after] by common prefix and suffix, which is
  /// exact for the single contiguous edit every real keystroke, paste, and
  /// programmatic insert produces.
  void _record(String before, String after) {
    final int limit = math.min(before.length, after.length);

    int prefix = 0;
    while (prefix < limit &&
        before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix++;
    }

    int suffix = 0;
    while (suffix < limit - prefix &&
        before.codeUnitAt(before.length - 1 - suffix) ==
            after.codeUnitAt(after.length - 1 - suffix)) {
      suffix++;
    }

    final int removed = before.length - prefix - suffix;
    final int inserted = after.length - prefix - suffix;

    _shift(at: prefix, removed: removed, inserted: inserted);
    if (inserted <= 0) return;

    final int now = _now;
    final _InkMark? last = _marks.isEmpty ? null : _marks.last;

    // Extend the previous mark when this keystroke lands right where the last
    // one ended, moments later. Held keys and pasted bursts collapse into one
    // wash instead of a hundred; anything slower keeps its own birth time.
    if (last != null &&
        last.end == prefix &&
        now - last.lastMs <= _coalesceMs) {
      last.end = prefix + inserted;
      last.lastMs = now;
    } else {
      _marks.add(_InkMark(start: prefix, end: prefix + inserted, bornMs: now));
    }

    _startTicking();
  }

  /// Rebases existing marks onto the post-edit text. Without this, typing at
  /// the top of a note would drag every older wash out of alignment with the
  /// words it belongs to.
  void _shift({required int at, required int removed, required int inserted}) {
    final int delta = inserted - removed;
    final int end = at + removed;

    for (final _InkMark mark in _marks) {
      if (mark.end <= at) continue;
      if (mark.start >= end) {
        mark.start += delta;
        mark.end += delta;
        continue;
      }
      // The edit ate into this mark. Keep only the part in front of it rather
      // than trying to track what survived: a wash that outlives the exact
      // characters it was painted on is worse than one that ends early.
      mark.start = math.min(mark.start, at);
      mark.end = math.min(mark.end, at);
    }

    _marks.removeWhere((_InkMark mark) => mark.isEmpty);
  }

  /// Quantised remaining life of [mark], from [_steps] down to 0.
  ///
  /// Quantising here rather than at paint time is what makes the whole thing
  /// affordable — see the class doc.
  int _levelOf(_InkMark mark, int now) {
    final double age = (now - mark.bornMs) / fade.inMilliseconds;
    if (age <= _hold) return _steps;
    final double life = 1.0 - (age - _hold) / (1.0 - _hold);
    return (life.clamp(0.0, 1.0) * _steps).round();
  }

  /// Cheap hash of everything that can change what the field paints.
  int _signature(int now) {
    int hash = _marks.length;
    for (final _InkMark mark in _marks) {
      hash = Object.hash(hash, mark.start, mark.end, _levelOf(mark, now));
    }
    return hash;
  }

  /// The ticker runs only while ink is wet, so it stops on its own about
  /// [fade] after the last keystroke. That self-limiting window is why a raw
  /// [Ticker] is acceptable here: it is never left running behind a hidden
  /// route long enough to matter.
  void _startTicking() {
    if (_disposed || _ticker != null) return;
    _ticker = Ticker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    _tickMs = elapsed.inMilliseconds;
    final int now = _now;
    _marks.removeWhere((_InkMark mark) => _levelOf(mark, now) <= 0);

    if (_marks.isEmpty) {
      _stopTicking();
    }

    // The frame only reaches the widget tree when it would look different.
    // Everything else is a tick that costs a comparison and nothing more.
    final int signature = _signature(now);
    if (signature == _published) return;
    _published = signature;
    ink.value++;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // An active IME composition owns its own underline styling. Fighting it
    // for one frame of wash would break CJK and mobile autocorrect input, so
    // the composition always wins.
    if (_marks.isEmpty || (withComposing && value.composing.isValid)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final String text = value.text;
    final Color base = color ?? Theme.of(context).colorScheme.primary;
    final int now = _now;

    final List<_InkMark> ordered =
        _marks
            .map(
              (_InkMark mark) => _InkMark(
                start: mark.start.clamp(0, text.length),
                end: mark.end.clamp(0, text.length),
                bornMs: mark.bornMs,
              ),
            )
            .where((_InkMark mark) => !mark.isEmpty)
            .toList()
          ..sort((_InkMark a, _InkMark b) => a.start.compareTo(b.start));

    final List<InlineSpan> spans = <InlineSpan>[];
    int cursor = 0;

    for (final _InkMark mark in ordered) {
      // Marks are kept disjoint by _shift, but a clamp above can collapse two
      // of them onto the same range. Dropping the second keeps the spans in
      // strict order, which TextSpan requires.
      if (mark.start < cursor) continue;
      if (mark.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, mark.start)));
      }

      final double level = _levelOf(mark, now) / _steps;
      spans.add(
        TextSpan(
          text: text.substring(mark.start, mark.end),
          style: TextStyle(
            backgroundColor: base.withValues(alpha: strength * level),
          ),
        ),
      );
      cursor = mark.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return TextSpan(style: style, children: spans);
  }

  /// Banks the run that is ending, so the next one resumes the same timeline
  /// instead of resetting every mark's age to zero.
  void _stopTicking() {
    if (_ticker == null) return;
    _ticker!.dispose();
    _ticker = null;
    _baseMs += _tickMs;
    _tickMs = 0;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTicking();
    ink.dispose();
    super.dispose();
  }
}

/// One stretch of text that was just written, when it landed, and when it last
/// grew — [lastMs] is what lets a fast run of keystrokes extend one mark
/// instead of piling up a hundred of them.
class _InkMark {
  _InkMark({required this.start, required this.end, required this.bornMs})
    : lastMs = bornMs;

  int start;
  int end;
  final int bornMs;
  int lastMs;

  bool get isEmpty => end <= start;
}
