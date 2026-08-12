// PathMetric lives in dart:ui and material.dart does not re-export it.
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

/// The confirmation that follows an autosave: a light that runs the card's
/// edge, once, and goes out.
///
/// It replaced a mark in the toolbar for a reason beyond taste. A status parked
/// in a row of buttons has to reserve width whether or not it is showing —
/// otherwise the row jumps every time a save lands — and that reserved space
/// pushed the whole toolbar off centre. A light on the border costs no layout
/// at all.
///
/// It also says the right thing. A tick beside the buttons confirms that a
/// control did something; a lap of the card confirms the card. The subject of
/// the sentence is the note, so the note is what should acknowledge it.
class SaveSweep extends StatefulWidget {
  const SaveSweep({
    super.key,
    required this.saved,
    this.radius = 20,
    this.thickness = 1.6,
  });

  final bool saved;

  /// Must match the card's own corner radius, or the light leaves the edge it
  /// is meant to be tracing.
  final double radius;
  final double thickness;

  @override
  State<SaveSweep> createState() => _SaveSweepState();
}

class _SaveSweepState extends State<SaveSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  );

  @override
  void initState() {
    super.initState();
    if (widget.saved) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant SaveSweep old) {
    super.didUpdateWidget(old);
    // Only the arrival matters. A save landing mid-lap restarts the run rather
    // than queueing a second light: two of them chasing each other reads as a
    // problem, not as two saves.
    if (widget.saved && !old.saved) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The whole thing is motion, so there is nothing to show when motion is
    // turned down. A border that lights up and goes dark is a flicker.
    if (MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _BorderTracePainter(
            progress: _controller.value,
            colour: Theme.of(context).colorScheme.primary,
            radius: widget.radius,
            thickness: widget.thickness,
          ),
        ),
      ),
    );
  }
}

/// Runs a comet once around a rounded rectangle.
class _BorderTracePainter extends CustomPainter {
  _BorderTracePainter({
    required this.progress,
    required this.colour,
    required this.radius,
    required this.thickness,
  });

  final double progress;
  final Color colour;
  final double radius;
  final double thickness;

  /// Length of the trail, as a share of the perimeter.
  static const _trail = 0.22;

  /// Pieces the trail is drawn in. Enough that the fade reads as a gradient
  /// rather than as steps, few enough to stay cheap on every frame.
  static const _steps = 22;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    // Inset by half the stroke so the light sits *on* the border rather than
    // straddling it and clipping against the card's own edge.
    final rect = Rect.fromLTWH(
      thickness / 2,
      thickness / 2,
      size.width - thickness,
      size.height - thickness,
    );
    if (rect.width <= 0 || rect.height <= 0) return;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius - thickness / 2)),
      );

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final perimeter = metric.length;

    // Eased, not linear: a constant lap reads as a machine scanning. This
    // leaves quickly and eases into its finish, the way a gesture does.
    final head = Curves.easeInOutCubic.transform(progress) * perimeter;

    // Fades over the last quarter so the light dies out instead of stopping.
    final strength =
        1 - Curves.easeIn.transform(((progress - 0.75) / 0.25).clamp(0.0, 1.0));
    if (strength <= 0) return;

    final trail = _trail * perimeter;

    for (var i = 0; i < _steps; i++) {
      // 0 at the head, 1 at the end of the trail.
      final back = i / _steps;
      final from = head - trail * (back + 1 / _steps);
      final to = head - trail * back;

      // Squared, so the light concentrates at the head and the tail thins out
      // rather than ending in a visible stub.
      final alpha = (1 - back) * (1 - back) * strength;
      if (alpha <= 0.01) continue;

      final segment = _extract(metric, from, to, perimeter);
      if (segment == null) continue;

      // A blurred pass under a crisp one: the glow is what makes it read as
      // light on the edge rather than as a moving line drawn on top of it.
      canvas.drawPath(
        segment,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness * 2.6
          ..strokeCap = StrokeCap.round
          ..color = colour.withValues(alpha: alpha * 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawPath(
        segment,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.round
          ..color = colour.withValues(alpha: alpha)
          ..isAntiAlias = true,
      );
    }
  }

  /// A piece of the outline, rejoined when it runs off the end of the path.
  ///
  /// The perimeter is a loop but its metric is not: extracting past the end
  /// silently returns nothing, which would make the trail vanish exactly as it
  /// turned the last corner.
  Path? _extract(PathMetric metric, double from, double to, double perimeter) {
    var start = from % perimeter;
    var end = to % perimeter;
    if (start < 0) start += perimeter;
    if (end < 0) end += perimeter;

    if (start <= end) return metric.extractPath(start, end);

    return Path()
      ..addPath(metric.extractPath(start, perimeter), Offset.zero)
      ..addPath(metric.extractPath(0, end), Offset.zero);
  }

  @override
  bool shouldRepaint(_BorderTracePainter old) =>
      old.progress != progress ||
      old.colour != colour ||
      old.radius != radius ||
      old.thickness != thickness;
}
