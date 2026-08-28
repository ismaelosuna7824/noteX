/// noteX's own renderer for `ul`, `ol` and `li`.
///
/// markdown_widget draws a list as a flat column of rows, one marker beside one
/// line of text, and that is all it offers: [ListConfig] exposes a left margin,
/// a bottom margin and a marker builder. Three things the notes needed are out
/// of reach behind that surface.
///
/// * **A visible tree.** Depth is currently communicated by indentation alone,
///   which stops reading past the second level. A rule down the left of each
///   nested block says where a branch begins and ends.
/// * **Folding.** A long checklist is unusable if the finished branches cannot
///   be put away.
/// * **Checking a box from the rendered side.** The preview draws checkboxes
///   the reader cannot press, so the only way to complete a task is to go back
///   to the source and edit `[ ]` by hand.
///
/// Folding in particular cannot be bolted on. The library's own `ListNode`
/// calls `children.removeAt(0)` inside `build()`, so building is destructive
/// and a node cannot be rendered twice; and a nested list lives inside the
/// parent item's [WidgetSpan], so there is no seam at which a subtree could be
/// hidden. Owning the three tags is what buys all three features at once.
library;

import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_widget/markdown_widget.dart';

/// Everything the list renderer needs to know about how the page looks.
class NoteXListStyle {
  const NoteXListStyle({
    required this.fontSize,
    required this.lineHeight,
    required this.textColor,
    required this.mutedColor,
    required this.accentColor,
    required this.guideColor,
  });

  final double fontSize;
  final double lineHeight;
  final Color textColor;
  final Color mutedColor;
  final Color accentColor;

  /// The rule drawn down the left of a nested block. Faint on purpose: it is
  /// there to be followed when you look for it, not to be read.
  final Color guideColor;

  /// Height of one line of item text, which every control in the gutter is
  /// centred against so markers sit on the text rather than above it.
  double get _row => fontSize * lineHeight;

  /// Width of the fold control. Also reserved when an item has nothing to
  /// fold, so markers stay in a column instead of stepping in and out as
  /// children come and go.
  double get _chevron => fontSize * 1.15;

  /// Width of the checkbox or bullet.
  double get _marker => fontSize * 1.5;

  /// How far a nested block is pushed in from its parent.
  double get indent => fontSize * 0.9;
}

/// Key of the fold control on the item with document-order index [itemIndex].
///
/// Public so a test can press the control the reader presses, rather than
/// reaching for a private widget type or guessing at a hit position.
ValueKey<String> markdownFoldKey(int itemIndex) =>
    ValueKey<String>('md-fold-$itemIndex');

/// Key of the checkbox on the task with document-order index [taskIndex].
ValueKey<String> markdownTaskKey(int taskIndex) =>
    ValueKey<String>('md-task-$taskIndex');

/// The per-render pass: ordinals, fold state, and the two callbacks.
///
/// A fresh one is made for every build of the view, because the ordinals are
/// assigned as the document is walked and have to start from zero each time.
class MarkdownListContext {
  MarkdownListContext({
    required this.collapsed,
    required this.onToggleCollapse,
    this.onToggleTask,
  });

  /// Keys of the items currently folded shut.
  final Set<String> collapsed;
  final ValueChanged<String> onToggleCollapse;

  /// Receives the document-order index of the task whose box was pressed. The
  /// same index `MarkdownTaskToggle` counts, which is the whole reason the two
  /// agree without either of them knowing about the other.
  final ValueChanged<int>? onToggleTask;

  int _items = 0;
  int _tasks = 0;

  /// Document-order index for the next list item.
  ///
  /// The visitor walks elements in pre-order, so calling this as each `li` is
  /// constructed numbers the items exactly as they are written.
  int nextItem() => _items++;

  /// Document-order index for the next task item.
  int nextTask() => _tasks++;
}

/// A list — `ul` or `ol` — and, through its items, everything below it.
class NoteXListNode extends ElementNode {
  NoteXListNode({
    required this.ordered,
    required this.start,
    required this.listStyle,
    required this.context,
  });

  final bool ordered;

  /// `<ol start="3">`. One-based in the source, kept one-based here.
  final int start;
  final NoteXListStyle listStyle;
  final MarkdownListContext context;

  List<NoteXListItemNode> get items =>
      children.whereType<NoteXListItemNode>().toList();

  /// Lays the list out as widgets.
  ///
  /// Nested lists are rendered through this method by their parent item, never
  /// through [build] — a list inside an item is part of that item's row, not a
  /// span floating in its text.
  Widget buildTree() {
    final List<NoteXListItemNode> entries = items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < entries.length; i++)
          entries[i].buildRow(ordinal: start + i, ordered: ordered),
      ],
    );
  }

  @override
  InlineSpan build() => WidgetSpan(child: buildTree());

  @override
  TextStyle? get style => parentStyle;
}

/// One `li`, its content, and the branch hanging off it.
class NoteXListItemNode extends ElementNode {
  NoteXListItemNode({
    required this.element,
    required this.listStyle,
    required this.context,
    required this.itemIndex,
    required this.taskIndex,
    required this.checked,
  });

  final md.Element element;
  final NoteXListStyle listStyle;
  final MarkdownListContext context;

  /// Document-order index among all list items, used as the fold key.
  ///
  /// An ordinal is not a durable identity — insert an item above and every key
  /// below it shifts, so a fold can move to its neighbour. The alternative is a
  /// path built from the element tree, which shifts under exactly the same
  /// edit. Neither survives a restructure, and the parser gives us nothing
  /// stabler to key on; an ordinal at least stays correct for every edit that
  /// does not change how many items come first.
  final int itemIndex;

  /// Index among task items, or null when this item has no checkbox.
  final int? taskIndex;
  final bool checked;

  bool get isTask => taskIndex != null;

  String get _foldKey => 'item-$itemIndex';

  NoteXListNode? get _sublist {
    for (final SpanNode child in children) {
      if (child is NoteXListNode) return child;
    }
    return null;
  }

  /// The item's own content — everything that is not the branch below it.
  List<SpanNode> get _content =>
      children.where((SpanNode child) => child is! NoteXListNode).toList();

  Widget buildRow({required int ordinal, required bool ordered}) {
    final NoteXListNode? sublist = _sublist;
    final bool foldable = sublist != null && sublist.items.isNotEmpty;
    final bool folded = foldable && context.collapsed.contains(_foldKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _Chevron(
              // Keyed only when there is something to fold, so finding the key
              // means finding a control rather than finding the blank that
              // holds its place.
              key: foldable ? markdownFoldKey(itemIndex) : null,
              style: listStyle,
              visible: foldable,
              folded: folded,
              onTap: () => context.onToggleCollapse(_foldKey),
            ),
            _marker(ordinal, ordered),
            Flexible(child: _text()),
          ],
        ),
        if (foldable && !folded)
          // The branch is drawn inside a container whose left edge is the rule.
          // Bounding it to the children means the rule starts where the branch
          // starts and stops where it stops, which is what makes it read as a
          // bracket around them rather than a margin decoration.
          Padding(
            padding: EdgeInsets.only(left: listStyle._chevron / 2),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: listStyle.guideColor, width: 1),
                ),
              ),
              padding: EdgeInsets.only(left: listStyle.indent),
              child: sublist.buildTree(),
            ),
          ),
      ],
    );
  }

  Widget _marker(int ordinal, bool ordered) {
    if (isTask) {
      return _Checkbox(
        key: markdownTaskKey(taskIndex!),
        style: listStyle,
        checked: checked,
        onTap: context.onToggleTask == null
            ? null
            : () => context.onToggleTask!(taskIndex!),
      );
    }
    return _Bullet(style: listStyle, ordered: ordered, ordinal: ordinal);
  }

  Widget _text() {
    final Widget rich = Text.rich(
      TextSpan(
        children: _content.map((SpanNode node) => node.build()).toList(),
        // The built spans already carry their own colour, so a colour set here
        // would not reach them — but they leave `decoration` alone, which is
        // why the strike lands and the fade has to come from Opacity instead.
        style: checked
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
    );

    if (!checked) return rich;
    return Opacity(opacity: 0.55, child: rich);
  }

  /// Only reached if an `li` somehow renders outside a list. The parser does
  /// not produce that, but a node that throws when asked to build is worse
  /// than one that draws a plain row.
  @override
  InlineSpan build() => WidgetSpan(child: buildRow(ordinal: 1, ordered: false));

  @override
  TextStyle? get style => parentStyle;
}

/// The fold control.
///
/// Reserves its width even with nothing to fold, so a list of leaves and a list
/// of branches put their markers in the same column.
class _Chevron extends StatelessWidget {
  const _Chevron({
    super.key,
    required this.style,
    required this.visible,
    required this.folded,
    required this.onTap,
  });

  final NoteXListStyle style;
  final bool visible;
  final bool folded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!visible) return SizedBox(width: style._chevron, height: style._row);

    return SelectionContainer.disabled(
      child: SizedBox(
        width: style._chevron,
        height: style._row,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Center(
              child: AnimatedRotation(
                // A quarter turn rather than swapping two icons: the rotation
                // says the same branch changed state, where a swap reads as a
                // different control appearing.
                turns: folded ? -0.25 : 0,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: style.fontSize * 1.05,
                  color: style.mutedColor.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A task checkbox that can actually be pressed.
class _Checkbox extends StatelessWidget {
  const _Checkbox({
    super.key,
    required this.style,
    required this.checked,
    required this.onTap,
  });

  final NoteXListStyle style;
  final bool checked;

  /// Null in a read-only surface, where the box still draws its state but does
  /// not pretend to be a control.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final double box = style.fontSize * 1.05;

    final Widget glyph = Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        color: checked ? style.accentColor : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: checked
              ? style.accentColor
              : style.mutedColor.withValues(alpha: 0.75),
          width: 1.6,
        ),
      ),
      child: checked
          ? Icon(Icons.check_rounded, size: box * 0.78, color: Colors.white)
          : null,
    );

    return SelectionContainer.disabled(
      child: SizedBox(
        width: style._marker,
        height: style._row,
        child: MouseRegion(
          cursor: onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Center(child: glyph),
          ),
        ),
      ),
    );
  }
}

/// The marker for an item that is not a task.
class _Bullet extends StatelessWidget {
  const _Bullet({
    required this.style,
    required this.ordered,
    required this.ordinal,
  });

  final NoteXListStyle style;
  final bool ordered;
  final int ordinal;

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: SizedBox(
        width: style._marker,
        height: style._row,
        child: Center(
          child: ordered
              ? Text(
                  '$ordinal.',
                  style: TextStyle(
                    fontSize: style.fontSize * 0.95,
                    color: style.mutedColor,
                    height: 1,
                  ),
                )
              : Container(
                  width: style.fontSize * 0.32,
                  height: style.fontSize * 0.32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: style.mutedColor.withValues(alpha: 0.8),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Renders nothing.
///
/// The parser emits an `<input>` for every task item, and this renderer draws
/// the checkbox itself from the element rather than from that span — the box
/// belongs in the gutter with the fold control, not inline at the head of the
/// text. Suppressing the span here is what keeps the library from drawing a
/// second one.
class MarkdownVoidNode extends SpanNode {
  @override
  InlineSpan build() => const TextSpan(text: '');
}

/// Reads a task item's checkbox out of the element the parser produced.
///
/// Two shapes have to be handled, and the difference is not cosmetic. A tight
/// list puts the `<input>` directly in the `<li>`; a loose list — one whose
/// items are separated by blank lines, or which has a nested block — wraps the
/// content in a `<p>` first. The same document can contain both, so a reader
/// that only knows one shape silently loses every checkbox in the other.
md.Element? findTaskInput(md.Element li) {
  final List<md.Node> children = li.children ?? const <md.Node>[];
  for (final md.Node child in children) {
    if (child is! md.Element) continue;
    if (child.tag == 'input') return child;
    if (child.tag == 'p') {
      for (final md.Node inner in child.children ?? const <md.Node>[]) {
        if (inner is md.Element && inner.tag == 'input') return inner;
      }
      // Only the first paragraph can hold the marker; anything after it is
      // body content.
      break;
    }
  }
  return null;
}

/// Lifts the children of a leading `<p>` up into the `<li>` itself.
///
/// A loose list wraps item content in a paragraph and a tight one does not, so
/// the two render with different spacing even when they were written to look
/// the same — and one blank line anywhere in a list flips every item in it.
/// Flattening here makes the two shapes identical before anything is drawn.
///
/// Safe to do in the generator: the visitor calls it from `visitElementBefore`
/// and only then walks `element.children`, so the replacement is what gets
/// visited.
void flattenLooseItem(md.Element li) {
  final List<md.Node>? children = li.children;
  if (children == null || children.isEmpty) return;

  final md.Node first = children.first;
  if (first is! md.Element || first.tag != 'p') return;

  li.children!
    ..removeAt(0)
    ..insertAll(0, first.children ?? const <md.Node>[]);
}
