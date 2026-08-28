import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_widget/markdown_widget.dart';

import 'markdown_blocks.dart';
import 'markdown_list.dart';

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

  NoteXListStyle get _list => NoteXListStyle(
        fontSize: baseFontSize,
        lineHeight: lineHeight,
        textColor: textColor,
        mutedColor: _muted,
        accentColor: accentColor,
        guideColor: _rule,
      );
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
class NoteXMarkdownView extends StatefulWidget {
  const NoteXMarkdownView({
    super.key,
    required this.data,
    required this.style,
    this.onTapLink,
    this.onToggleTask,
  });

  final String data;
  final NoteXMarkdownStyle style;

  /// Receives the raw href, including the app's own `notex://` note links.
  final ValueChanged<String>? onTapLink;

  /// Receives the document-order index of a task whose checkbox was pressed.
  ///
  /// The view does not edit the source itself — it does not own it. The host
  /// applies the change with `MarkdownTaskToggle.toggle`, which counts tasks
  /// the same way this renderer numbers them. Leave it null and the boxes draw
  /// their state without offering to change it, which is what a read-only
  /// surface wants.
  final ValueChanged<int>? onToggleTask;

  @override
  State<NoteXMarkdownView> createState() => _NoteXMarkdownViewState();
}

class _NoteXMarkdownViewState extends State<NoteXMarkdownView> {
  /// Fold keys of the branches currently shut.
  ///
  /// Fold state is a property of this view, not of the note: it says what the
  /// reader is looking at right now, and writing it into the Markdown would
  /// mean a note that looks different depending on who last collapsed
  /// something. It lasts as long as the view is on screen.
  final Set<String> _collapsed = <String>{};

  NoteXMarkdownStyle get style => widget.style;

  @override
  Widget build(BuildContext context) {
    // One pass per build: the ordinals are handed out as the document is
    // walked, so they have to start again from zero every time.
    final listContext = MarkdownListContext(
      collapsed: _collapsed,
      onToggleCollapse: (key) => setState(() {
        if (!_collapsed.remove(key)) _collapsed.add(key);
      }),
      onToggleTask: widget.onToggleTask,
    );

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
          tag: 'ul',
          generator: (element, config, visitor) => NoteXListNode(
            ordered: false,
            start: 1,
            listStyle: style._list,
            context: listContext,
          ),
        ),
        SpanNodeGeneratorWithTag(
          tag: 'ol',
          generator: (element, config, visitor) => NoteXListNode(
            ordered: true,
            start: int.tryParse(element.attributes['start'] ?? '') ?? 1,
            listStyle: style._list,
            context: listContext,
          ),
        ),
        SpanNodeGeneratorWithTag(
          tag: 'li',
          generator: (element, config, visitor) {
            // Both of these read or rewrite the element before the visitor
            // walks its children, which is the only moment either is possible.
            flattenLooseItem(element);
            final input = findTaskInput(element);
            return NoteXListItemNode(
              element: element,
              listStyle: style._list,
              context: listContext,
              itemIndex: listContext.nextItem(),
              taskIndex: input == null ? null : listContext.nextTask(),
              checked: input?.attributes['checked']?.toLowerCase() == 'true',
            );
          },
        ),
        SpanNodeGeneratorWithTag(
          tag: 'input',
          // The checkbox is drawn in the gutter by the item, not inline here.
          generator: (element, config, visitor) => MarkdownVoidNode(),
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
      children: generator.buildWidgets(widget.data, config: _config()),
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
          onTap: widget.onTapLink,
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
