import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_widget/markdown_widget.dart';

import 'markdown_blocks.dart';

/// The per-surface knobs. Everything else about how Markdown renders is fixed
/// in [NoteXMarkdownView] so the three editing surfaces cannot drift apart —
/// which they had, each declaring its own builders and extension set.
class NoteXMarkdownStyle {
  const NoteXMarkdownStyle({
    required this.isDark,
    required this.baseFontSize,
    required this.lineHeight,
    required this.textColor,
    required this.accentColor,
    required this.surfaceColor,
  });

  final bool isDark;
  final double baseFontSize;
  final double lineHeight;
  final Color textColor;
  final Color accentColor;

  /// The panel the preview is drawn on. Diagrams are themed against it so a
  /// rendered SVG does not arrive carrying its own white page.
  final Color surfaceColor;

  double get _scale => baseFontSize / 16;

  Color get _rule => isDark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.black.withValues(alpha: 0.12);

  Color get _muted => textColor.withValues(alpha: 0.65);

  Color get _codeBg => isDark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.black.withValues(alpha: 0.05);

  Color get _codeBorder => isDark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.black.withValues(alpha: 0.08);

  BoxDecoration get _codeBox => BoxDecoration(
        color: _codeBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _codeBorder),
      );

  TextStyle get _codeText => TextStyle(
        fontFamily: 'monospace',
        fontSize: (baseFontSize * 0.92).roundToDouble(),
        color: textColor,
      );

  double _heading(double size) => (size * _scale).roundToDouble();
}

/// Renders Markdown the way noteX renders Markdown — everywhere.
///
/// Feature set is GitHub's: tables, task lists, strikethrough, autolinks,
/// footnotes, emoji shortcodes, alert callouts and heading anchors, plus
/// syntax-highlighted code and mermaid diagrams.
///
/// Returns a plain [Column] of blocks rather than its own scroll view, so the
/// caller decides how it scrolls and can wrap the whole thing in one
/// [SelectionArea] — selection has to cross block boundaries to be worth
/// anything.
class NoteXMarkdownView extends StatelessWidget {
  const NoteXMarkdownView({
    super.key,
    required this.data,
    required this.style,
    this.onTapLink,
  });

  final String data;
  final NoteXMarkdownStyle style;

  /// Receives the raw href, including the app's own `notex://` note links.
  final ValueChanged<String>? onTapLink;

  @override
  Widget build(BuildContext context) {
    final generator = MarkdownGenerator(
      // gitHubWeb rather than gitHubFlavored: it is what adds alert callouts,
      // `:emoji:` shortcodes and heading ids. gitHubFlavored parsed none of
      // them, so `> [!WARNING]` used to render as a quote with the literal
      // marker still in it.
      extensionSet: md.ExtensionSet.gitHubWeb,
      generators: [
        SpanNodeGeneratorWithTag(
          tag: 'pre',
          generator: (element, config, visitor) => isMermaidFence(element)
              ? _MermaidNode(element: element, mdStyle: style)
              // Not a diagram: hand it straight back to the library so fenced
              // code keeps its syntax highlighting.
              : CodeBlockNode(element, config.pre, visitor),
        ),
        SpanNodeGeneratorWithTag(
          tag: 'div',
          generator: (element, config, visitor) {
            final kind = AlertKind.fromClass(element.attributes['class']);
            // The only <div> Markdown produces is an alert, but anything else
            // that slips through should render as ordinary content, not vanish.
            return kind == null
                ? ConcreteElementNode(tag: 'div')
                : AlertNode(
                    kind: kind,
                    isDark: style.isDark,
                    textColor: style.textColor,
                  );
          },
        ),
        SpanNodeGeneratorWithTag(
          tag: 'sup',
          generator: (element, config, visitor) =>
              FootnoteRefNode(color: style.accentColor),
        ),
        SpanNodeGeneratorWithTag(
          tag: 'section',
          generator: (element, config, visitor) => FootnoteSectionNode(
            ruleColor: style._rule,
            textColor: style._muted,
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: generator.buildWidgets(data, config: _config()),
    );
  }

  MarkdownConfig _config() {
    final body = TextStyle(
      fontSize: style.baseFontSize,
      height: style.lineHeight,
      color: style.textColor,
    );

    return MarkdownConfig(
      configs: [
        PConfig(textStyle: body),
        H1Config(
          style: TextStyle(
            fontSize: style._heading(28),
            fontWeight: FontWeight.w800,
            color: style.textColor,
          ),
        ),
        H2Config(
          style: TextStyle(
            fontSize: style._heading(22),
            fontWeight: FontWeight.w700,
            color: style.textColor,
          ),
        ),
        H3Config(
          style: TextStyle(
            fontSize: style._heading(18),
            fontWeight: FontWeight.w600,
            color: style.textColor,
          ),
        ),
        H4Config(
          style: TextStyle(
            fontSize: style._heading(16),
            fontWeight: FontWeight.w600,
            color: style.textColor,
          ),
        ),
        H5Config(
          style: TextStyle(
            fontSize: style._heading(15),
            fontWeight: FontWeight.w600,
            color: style._muted,
          ),
        ),
        H6Config(
          style: TextStyle(
            fontSize: style._heading(14),
            fontWeight: FontWeight.w600,
            color: style._muted,
          ),
        ),
        LinkConfig(
          style: TextStyle(
            color: style.accentColor,
            decoration: TextDecoration.underline,
            decorationColor: style.accentColor.withValues(alpha: 0.4),
          ),
          onTap: onTapLink,
        ),
        BlockquoteConfig(sideColor: style.accentColor.withValues(alpha: 0.5)),
        HrConfig(color: style._rule),
        CodeConfig(
          style: style._codeText.copyWith(
            backgroundColor: style._codeBg,
          ),
        ),
        PreConfig(
          decoration: style._codeBox,
          textStyle: style._codeText,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.symmetric(vertical: 4),
          // Highlight palettes matched to the surface, so code does not glow
          // white on a dark page or grey out on a light one.
          theme: style.isDark ? atomOneDarkTheme : atomOneLightTheme,
          styleNotMatched: style._codeText,
        ),
        TableConfig(
          border: TableBorder.all(color: style._rule),
        ),
        CheckBoxConfig(
          builder: (checked) => Padding(
            padding: const EdgeInsets.only(right: 6, top: 2),
            child: Icon(
              checked ? Icons.check_box_rounded : Icons.check_box_outline_blank,
              size: style.baseFontSize,
              color: checked ? style.accentColor : style._muted,
            ),
          ),
        ),
      ],
    );
  }
}

/// A mermaid fence as a node, so the diagram sits in the document flow like any
/// other block.
class _MermaidNode extends ElementNode {
  // Not named `style`: SpanNode already owns that name for a TextStyle.
  _MermaidNode({required this.element, required this.mdStyle});

  final md.Element element;
  final NoteXMarkdownStyle mdStyle;

  @override
  InlineSpan build() => WidgetSpan(
        child: MermaidBlock(
          source: element.textContent.trimRight(),
          isDark: mdStyle.isDark,
          codeStyle: mdStyle._codeText,
          decoration: mdStyle._codeBox,
          background: mdStyle.surfaceColor,
        ),
      );
}
