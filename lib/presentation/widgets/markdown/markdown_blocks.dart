import 'package:duskmoon_mermaid_renderer/duskmoon_mermaid_renderer.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_widget/markdown_widget.dart';

/// The Markdown blocks noteX renders that markdown_widget does not know about.
///
/// Each one is an [ElementNode], which matters: the library builds this node's
/// children and hands them over as [childrenSpan]. A callout keeps the bold,
/// the links and the inline code inside it without any of that being
/// reimplemented here — which is the whole reason the preview moved onto this
/// renderer.

// ── GitHub alerts ───────────────────────────────────────────────────────────

/// The five callout kinds GitHub defines, and how each one presents itself.
enum AlertKind {
  note('note', 'Note', Icons.info_outline_rounded, Color(0xFF539BF5)),
  tip('tip', 'Tip', Icons.lightbulb_outline_rounded, Color(0xFF57AB5A)),
  important('important', 'Important', Icons.campaign_outlined, Color(0xFF986EE2)),
  warning('warning', 'Warning', Icons.warning_amber_rounded, Color(0xFFC69026)),
  caution('caution', 'Caution', Icons.report_gmailerrorred_rounded, Color(0xFFE5534B));

  const AlertKind(this.slug, this.label, this.icon, this.color);

  /// The token the parser puts in the element's class, e.g. `markdown-alert-tip`.
  final String slug;
  final String label;
  final IconData icon;

  /// Hue for the rail, icon and title. These are GitHub's own alert colours
  /// rather than the app accent: a caution that adopts the user's accent is a
  /// caution that stops reading as one.
  final Color color;

  static AlertKind? fromClass(String? className) {
    if (className == null) return null;
    for (final kind in AlertKind.values) {
      if (className.contains('markdown-alert-${kind.slug}')) return kind;
    }
    return null;
  }
}

/// `> [!WARNING]` and friends, drawn as a callout.
///
/// The parser emits `<div class="markdown-alert markdown-alert-warning">` with
/// a `<p class="markdown-alert-title">` first child. That title paragraph is
/// dropped here and redrawn beside the icon, because the parser writes it in
/// English and the app should not print "Warning" above a Spanish sentence
/// purely because of where the Markdown came from.
class AlertNode extends ElementNode {
  AlertNode({required this.kind, required this.isDark, required this.textColor});

  final AlertKind kind;
  final bool isDark;
  final Color textColor;

  @override
  InlineSpan build() {
    // Skip the title paragraph the parser generated; the header below replaces
    // it. Everything after it is the author's own content.
    final body = children.length > 1 ? children.sublist(1) : children;

    return WidgetSpan(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: kind.color.withValues(alpha: isDark ? 0.10 : 0.07),
          borderRadius: BorderRadius.circular(8),
          // A rail rather than a full border: it marks the block without
          // boxing the text, which is what keeps a page of callouts readable.
          border: Border(left: BorderSide(color: kind.color, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(kind.icon, size: 16, color: kind.color),
                const SizedBox(width: 7),
                Text(
                  kind.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kind.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(children: body.map((child) => child.build()).toList()),
              style: TextStyle(color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Footnotes ───────────────────────────────────────────────────────────────

/// The `[^1]` marker in the body text, drawn as a real superscript.
///
/// Without this the reference number sits on the baseline glued to the word
/// before it, which reads as a typo rather than a footnote.
class FootnoteRefNode extends ElementNode {
  FootnoteRefNode({required this.color});

  final Color color;

  @override
  InlineSpan build() => WidgetSpan(
        alignment: PlaceholderAlignment.top,
        child: Transform.translate(
          offset: const Offset(1, -1),
          child: Text.rich(
            childrenSpan,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      );
}

/// The block of footnote definitions the parser appends at the end.
///
/// Given a rule and smaller type so it reads as apparatus rather than as one
/// more paragraph of the document.
class FootnoteSectionNode extends ElementNode {
  FootnoteSectionNode({required this.ruleColor, required this.textColor});

  final Color ruleColor;
  final Color textColor;

  @override
  InlineSpan build() => WidgetSpan(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 20),
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: ruleColor)),
          ),
          child: Text.rich(
            childrenSpan,
            style: TextStyle(fontSize: 13, color: textColor),
          ),
        ),
      );
}

// ── Mermaid ─────────────────────────────────────────────────────────────────

/// A ```mermaid fence, drawn as a diagram.
///
/// Rendering is pure Dart — no WebView. That is not a preference: webview
/// packages do not cover Linux, and noteX ships Linux.
///
/// A diagram that fails to parse falls back to showing its source. Someone
/// mid-sentence in a diagram should see what they typed, not an empty box or a
/// stack trace: the fallback IS the editing experience, not an error path.
class MermaidBlock extends StatefulWidget {
  const MermaidBlock({
    super.key,
    required this.source,
    required this.isDark,
    required this.codeStyle,
    required this.decoration,
  });

  final String source;
  final bool isDark;
  final TextStyle codeStyle;
  final BoxDecoration decoration;

  @override
  State<MermaidBlock> createState() => _MermaidBlockState();
}

class _MermaidBlockState extends State<MermaidBlock> {
  String? _error;
  bool _hovering = false;

  @override
  void didUpdateWidget(covariant MermaidBlock old) {
    super.didUpdateWidget(old);
    // New source deserves a fresh verdict — otherwise a diagram that failed
    // once stays broken for the rest of the session while the user fixes it.
    if (old.source != widget.source) _error = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _fallback();

    final diagram = DmMermaidView(
      source: widget.source,
      options: MermaidRenderOptions(
        theme: widget.isDark ? MermaidTheme.dark : MermaidTheme.light,
      ),
      // setState during layout would loop; defer to after the frame.
      onError: (error) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _error = error.toString());
        });
      },
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: widget.decoration,
        child: Stack(
          children: [
            // The diagram itself takes no gestures. It sits inside a scrolling
            // note, and a pannable canvas here would swallow the drag that was
            // meant to scroll the page — the reader would hit a dead zone in
            // the middle of their own document. Zooming happens in the viewer.
            diagram,
            Positioned(
              top: 0,
              right: 0,
              child: _ExpandButton(
                color: widget.codeStyle.color ?? Colors.grey,
                prominent: _hovering,
                onPressed: _openViewer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openViewer() {
    showDialog<void>(
      context: context,
      // Barrier over a full-screen surface: the diagram is the task now, and
      // the note behind it stays visible enough to keep your place.
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => MermaidViewer(
        source: widget.source,
        isDark: widget.isDark,
      ),
    );
  }

  Widget _fallback() => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: widget.decoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 14,
                  color: widget.codeStyle.color?.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Text(
                  'mermaid',
                  style: widget.codeStyle.copyWith(
                    fontSize: 11,
                    color: widget.codeStyle.color?.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(widget.source, style: widget.codeStyle),
            ),
          ],
        ),
      );
}

/// Whether a fenced block should be drawn as a diagram rather than as code.
bool isMermaidFence(md.Element element) {
  final first = element.children?.firstOrNull;
  if (first is! md.Element) return false;
  return first.attributes['class']?.split('-').last.toLowerCase() == 'mermaid';
}

/// The corner affordance that opens the viewer.
///
/// Faint at rest and brighter on hover, rather than hidden until hover: a
/// control nobody can see is a control nobody uses, and this is the only way
/// to read a diagram that got scaled down to fit.
class _ExpandButton extends StatelessWidget {
  const _ExpandButton({
    required this.color,
    required this.prominent,
    required this.onPressed,
  });

  final Color color;
  final bool prominent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: prominent ? 1 : 0.35,
      duration: const Duration(milliseconds: 150),
      child: IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.open_in_full_rounded, size: 15),
        color: color,
        visualDensity: VisualDensity.compact,
        tooltip: 'Zoom diagram',
      ),
    );
  }
}

/// A diagram on its own, where panning and zooming cost nothing.
///
/// This exists because the inline block deliberately takes no gestures: it
/// lives inside a scrolling note, and a pannable canvas there would eat the
/// drag meant to scroll the page. Here there is no page to scroll, so the
/// canvas can have every gesture it wants.
class MermaidViewer extends StatefulWidget {
  const MermaidViewer({super.key, required this.source, required this.isDark});

  final String source;
  final bool isDark;

  @override
  State<MermaidViewer> createState() => _MermaidViewerState();
}

class _MermaidViewerState extends State<MermaidViewer> {
  final _controller = TransformationController();

  static const _minScale = 0.5;
  static const _maxScale = 6.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _scale => _controller.value.getMaxScaleOnAxis();

  /// Zooms about the centre of the viewport, which is where someone looking at
  /// a diagram already is. Scaling about the origin would walk the drawing off
  /// the top-left corner a step at a time.
  void _zoomBy(double factor, Size viewport) {
    final target = (_scale * factor).clamp(_minScale, _maxScale);
    final applied = target / _scale;
    if (applied == 1) return;

    final centre = Offset(viewport.width / 2, viewport.height / 2);
    _controller.value = Matrix4.copy(_controller.value)
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..scaleByDouble(applied, applied, 1, 1)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
    setState(() {});
  }

  void _reset() {
    _controller.value = Matrix4.identity();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final surface = isDark ? const Color(0xFF16161B) : Colors.white;
    final foreground = isDark ? Colors.white : Colors.black87;

    return Dialog(
      backgroundColor: surface,
      insetPadding: const EdgeInsets.all(32),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);

          return Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: _minScale,
                  maxScale: _maxScale,
                  // Room to drag a zoomed diagram past the edges instead of
                  // hitting an invisible wall mid-gesture.
                  boundaryMargin: const EdgeInsets.all(600),
                  onInteractionEnd: (_) => setState(() {}),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: DmMermaidView(
                        source: widget.source,
                        options: MermaidRenderOptions(
                          theme:
                              isDark ? MermaidTheme.dark : MermaidTheme.light,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              Positioned(
                top: 10,
                right: 10,
                child: Row(
                  children: [
                    _ViewerButton(
                      icon: Icons.remove_rounded,
                      tooltip: 'Zoom out',
                      color: foreground,
                      onPressed: _scale > _minScale
                          ? () => _zoomBy(1 / 1.3, viewport)
                          : null,
                    ),
                    // Doubles as a readout: without it there is no way to tell
                    // how far in you are, or that a button stopped responding
                    // because you hit the limit.
                    SizedBox(
                      width: 52,
                      child: Text(
                        '${(_scale * 100).round()}%',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: foreground.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    _ViewerButton(
                      icon: Icons.add_rounded,
                      tooltip: 'Zoom in',
                      color: foreground,
                      onPressed: _scale < _maxScale
                          ? () => _zoomBy(1.3, viewport)
                          : null,
                    ),
                    _ViewerButton(
                      icon: Icons.fit_screen_rounded,
                      tooltip: 'Reset',
                      color: foreground,
                      onPressed: _controller.value.isIdentity() ? null : _reset,
                    ),
                    const SizedBox(width: 4),
                    _ViewerButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Close',
                      color: foreground,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ViewerButton extends StatelessWidget {
  const _ViewerButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        color: color.withValues(alpha: 0.75),
        disabledColor: color.withValues(alpha: 0.2),
        visualDensity: VisualDensity.compact,
        tooltip: tooltip,
      );
}
