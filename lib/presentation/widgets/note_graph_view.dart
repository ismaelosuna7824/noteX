import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/services/force_layout.dart';
import '../../domain/services/note_graph.dart';

/// Interactive rendering of a [NoteGraph]: pan, zoom, drag nodes, hover to
/// highlight, tap to open.
///
/// The layout arrives already solved from [ForceLayout]; this widget only
/// displays it and lets a person move things around. Keeping the simulation
/// outside the widget is what makes it testable, and means resizing the window
/// does not silently reshuffle a graph someone had arranged by hand.
class NoteGraphView extends StatefulWidget {
  final NoteGraph graph;

  /// Solved positions in layout space, keyed by note id.
  final Map<String, LayoutPoint> positions;

  final Color accentColor;
  final ValueChanged<String> onOpenNote;

  const NoteGraphView({
    super.key,
    required this.graph,
    required this.positions,
    required this.accentColor,
    required this.onOpenNote,
  });

  @override
  State<NoteGraphView> createState() => _NoteGraphViewState();
}

class _NoteGraphViewState extends State<NoteGraphView> {
  /// Node positions in layout space, mutated as the user drags them.
  late Map<String, Offset> _positions;

  /// Canvas transform. Pan and zoom are tracked here rather than through
  /// InteractiveViewer, because dragging a node and panning the canvas are the
  /// same gesture and only one widget can decide which is happening.
  Offset _pan = Offset.zero;
  double _zoom = 1;

  String? _hovered;
  String? _selected;

  /// Node currently being dragged, if any. While set, the gesture moves that
  /// node instead of the canvas.
  String? _dragging;

  Offset _gestureStartPan = Offset.zero;
  double _gestureStartZoom = 1;
  Offset _gestureStartFocal = Offset.zero;

  static const _minZoom = 0.25;
  static const _maxZoom = 3.0;

  @override
  void initState() {
    super.initState();
    _adoptPositions();
  }

  @override
  void didUpdateWidget(covariant NoteGraphView old) {
    super.didUpdateWidget(old);
    // Only re-seed when the solved layout itself changed. Re-adopting on every
    // rebuild would throw away nodes the user had dragged into place.
    if (!identical(old.positions, widget.positions)) _adoptPositions();
  }

  /// Whether the graph has been framed for the current layout yet.
  bool _needsFit = true;

  /// Viewport the current framing was computed for, so a resize can be told
  /// apart from an ordinary rebuild.
  Size? _fittedFor;

  void _adoptPositions() {
    _positions = {
      for (final entry in widget.positions.entries)
        entry.key: Offset(entry.value.x, entry.value.y),
    };
    // A fresh layout has not been framed. Without this the view opens at
    // zoom 1 on the top-left corner of a 1600x1100 space and shows a slice of
    // the graph with everything else off screen.
    _needsFit = true;
  }

  /// Radius a node is drawn at. Grows with how connected it is, so the notes
  /// everything points at are the ones the eye lands on first.
  double _radiusOf(GraphNode node) => 6 + math.min(node.degree, 8) * 1.6;

  Offset _toLayout(Offset screenPoint) => (screenPoint - _pan) / _zoom;

  /// The node under [screenPoint], preferring the one drawn on top.
  String? _hitTest(Offset screenPoint) {
    final point = _toLayout(screenPoint);

    // Reverse order: the list is sorted hubs-first for painting, so the last
    // painted is the topmost and should win a tie.
    for (final node in widget.graph.nodes.reversed) {
      final position = _positions[node.id];
      if (position == null) continue;

      // A generous target: nodes are small, and a person should not have to
      // hit a 12px circle exactly.
      final reach = math.max(_radiusOf(node) + 8, 20 / _zoom);
      if ((position - point).distance <= reach) return node.id;
    }
    return null;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartFocal = details.localFocalPoint;
    _gestureStartPan = _pan;
    _gestureStartZoom = _zoom;

    final hit = _hitTest(details.localFocalPoint);
    // A single finger on a node drags it; anything else moves the canvas.
    _dragging = details.pointerCount == 1 ? hit : null;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      final dragging = _dragging;
      if (dragging != null) {
        _positions[dragging] = _toLayout(details.localFocalPoint);
        return;
      }

      final nextZoom = (_gestureStartZoom * details.scale).clamp(_minZoom, _maxZoom);

      // Keep whatever is under the fingers under the fingers: without this,
      // zooming drifts the graph away from what the user was looking at.
      final focalInLayout = (_gestureStartFocal - _gestureStartPan) / _gestureStartZoom;
      _pan = details.localFocalPoint - focalInLayout * nextZoom;
      _zoom = nextZoom;
    });
  }

  void _onScaleEnd(ScaleEndDetails details) => _dragging = null;

  void _onTapUp(TapUpDetails details) {
    final hit = _hitTest(details.localPosition);
    if (hit == null) {
      setState(() => _selected = null);
      return;
    }
    // First tap selects and reveals the neighbourhood; a tap on the already
    // selected node opens it. Opening on first tap would make it impossible to
    // study a node without leaving the graph.
    if (_selected == hit) {
      widget.onOpenNote(hit);
    } else {
      setState(() => _selected = hit);
    }
  }

  /// Fits the whole graph into [viewport] with a margin.
  void _fitToView(Size viewport) {
    if (_positions.isEmpty) return;

    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final position in _positions.values) {
      minX = math.min(minX, position.dx);
      maxX = math.max(maxX, position.dx);
      minY = math.min(minY, position.dy);
      maxY = math.max(maxY, position.dy);
    }

    const margin = 60.0;
    final spread = Size(math.max(maxX - minX, 1), math.max(maxY - minY, 1));
    final zoom = math.min(
      (viewport.width - margin * 2) / spread.width,
      (viewport.height - margin * 2) / spread.height,
    ).clamp(_minZoom, _maxZoom);

    setState(() {
      _zoom = zoom;
      _pan = Offset(
            viewport.width / 2 - (minX + spread.width / 2) * zoom,
            viewport.height / 2 - (minY + spread.height / 2) * zoom,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final highlighted = _selected ?? _hovered;
    final neighbours = highlighted == null
        ? const <String>{}
        : widget.graph.neighboursOf(highlighted);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);

        // Frame the graph once the viewport is known, and again if it changes
        // shape — the panel's width follows the window, and a framing computed
        // for the old size leaves the graph off to one side.
        final resized = _fittedFor != null &&
            ((_fittedFor!.width - viewport.width).abs() > 24 ||
                (_fittedFor!.height - viewport.height).abs() > 24);

        if ((_needsFit || resized) && viewport.width > 0 && viewport.height > 0) {
          _needsFit = false;
          _fittedFor = viewport;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _fitToView(viewport);
          });
        }

        return Stack(
          children: [
            MouseRegion(
              onHover: (event) {
                final hit = _hitTest(event.localPosition);
                if (hit != _hovered) setState(() => _hovered = hit);
              },
              onExit: (_) => setState(() => _hovered = null),
              cursor: _hovered != null ? SystemMouseCursors.click : SystemMouseCursors.grab,
              child: GestureDetector(
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                onTapUp: _onTapUp,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _GraphPainter(
                    graph: widget.graph,
                    positions: _positions,
                    pan: _pan,
                    zoom: _zoom,
                    highlighted: highlighted,
                    neighbours: neighbours,
                    accentColor: widget.accentColor,
                    radiusOf: _radiusOf,
                    isDark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
              ),
            ),

            Positioned(
              right: 16,
              bottom: 16,
              child: _Controls(
                accentColor: widget.accentColor,
                onZoomIn: () => setState(() => _zoom = (_zoom * 1.25).clamp(_minZoom, _maxZoom)),
                onZoomOut: () => setState(() => _zoom = (_zoom / 1.25).clamp(_minZoom, _maxZoom)),
                onFit: () => _fitToView(viewport),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GraphPainter extends CustomPainter {
  final NoteGraph graph;
  final Map<String, Offset> positions;
  final Offset pan;
  final double zoom;
  final String? highlighted;
  final Set<String> neighbours;
  final Color accentColor;
  final double Function(GraphNode) radiusOf;
  final bool isDark;

  _GraphPainter({
    required this.graph,
    required this.positions,
    required this.pan,
    required this.zoom,
    required this.highlighted,
    required this.neighbours,
    required this.accentColor,
    required this.radiusOf,
    required this.isDark,
  });

  /// Whether a node should be drawn at full strength: everything is, until
  /// something is highlighted, at which point only it and its neighbours are.
  bool _isLit(String id) =>
      highlighted == null || id == highlighted || neighbours.contains(id);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(zoom);

    final baseLine = isDark ? Colors.white : Colors.black;

    // Edges first, so nodes sit on top of their own connections.
    for (final edge in graph.edges) {
      final from = positions[edge.sourceId];
      final to = positions[edge.targetId];
      if (from == null || to == null) continue;

      final lit = _isLit(edge.sourceId) && _isLit(edge.targetId);
      final touchesHighlight =
          highlighted != null && (edge.sourceId == highlighted || edge.targetId == highlighted);

      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = touchesHighlight
              ? accentColor.withValues(alpha: 0.9)
              : baseLine.withValues(alpha: lit ? 0.22 : 0.06)
          ..strokeWidth = (touchesHighlight ? 1.6 : 0.9) / zoom
          ..isAntiAlias = true,
      );
    }

    for (final node in graph.nodes) {
      final position = positions[node.id];
      if (position == null) continue;

      final lit = _isLit(node.id);
      final isFocus = node.id == highlighted;
      final radius = radiusOf(node);

      // A halo marks the focused node without moving or resizing it, so the
      // graph does not jump when the pointer crosses a node.
      if (isFocus) {
        canvas.drawCircle(
          position,
          radius + 6,
          Paint()..color = accentColor.withValues(alpha: 0.22),
        );
      }

      // Neutral fills, brightening with how connected a note is. Size and
      // value carry the hierarchy; the accent is spent only on what is
      // focused, so it still means something when it appears.
      final connectedness = math.min(node.degree, 6) / 6;
      final restColor = baseLine.withValues(
        alpha: (0.32 + connectedness * 0.55) * (lit ? 1 : 0.22),
      );

      canvas.drawCircle(
        position,
        radius,
        Paint()..color = isFocus ? accentColor : restColor,
      );

      // Labels are earned, not given. Forty of them at once is a wall of text
      // with a graph hidden behind it, so they appear on the focused note
      // always, and on the rest only once zoomed in far enough to read them
      // without overlap.
      final showLabel = isFocus || zoom >= 0.95;
      if (!showLabel) continue;

      final painter = TextPainter(
        text: TextSpan(
          text: node.title,
          style: TextStyle(
            // Divided by zoom so labels keep a constant on-screen size instead
            // of growing into slabs as the canvas scales up.
            fontSize: 11 / zoom,
            fontWeight: isFocus ? FontWeight.w600 : FontWeight.w400,
            color: baseLine.withValues(alpha: lit ? (isFocus ? 0.95 : 0.6) : 0.12),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 140 / zoom);

      painter.paint(
        canvas,
        position + Offset(-painter.width / 2, radius + 5 / zoom),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.positions != positions ||
      old.pan != pan ||
      old.zoom != zoom ||
      old.highlighted != highlighted ||
      old.graph != graph;
}

class _Controls extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  const _Controls({
    required this.accentColor,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget button(IconData icon, String tooltip, VoidCallback onTap) => Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            // 44x44: the visible button can be smaller than the thing you have
            // to hit, the hit area cannot.
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, size: 18, color: isDark ? Colors.white70 : Colors.black54),
            ),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(Icons.remove_rounded, 'Zoom out', onZoomOut),
          button(Icons.add_rounded, 'Zoom in', onZoomIn),
          button(Icons.fit_screen_outlined, 'Fit to view', onFit),
        ],
      ),
    );
  }
}
