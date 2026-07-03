import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Shared code styling for the Markdown preview, so the note editor and the
/// Markdown page render code identically: a subtle full-width box, monospace
/// text in the CURRENT text color, and NO per-span highlight.
///
/// [decoration] is the box drawn behind fenced code blocks; [textStyle] is the
/// monospace style used for BOTH inline `code` and block code text.
class MarkdownCodeStyles {
  const MarkdownCodeStyles({
    required this.decoration,
    required this.textStyle,
  });

  /// The full-width fenced-code-block box (subtle background + rounded border).
  final BoxDecoration decoration;

  /// Monospace style for code text (no background highlight). Applies to inline
  /// `code` and fenced code blocks so both read as the current text color.
  final TextStyle textStyle;

  /// Builds the shared code styles from the preview's [isDark] flag, its base
  /// [baseFont] size, and the [color] of the surrounding text. The code text
  /// keeps [color] — there is no coloured highlight.
  factory MarkdownCodeStyles.from({
    required bool isDark,
    required double baseFont,
    required Color color,
  }) {
    final codeBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);
    final codeBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);
    return MarkdownCodeStyles(
      decoration: BoxDecoration(
        color: codeBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: codeBorder, width: 1),
      ),
      textStyle: TextStyle(
        fontFamily: 'monospace',
        fontSize: (baseFont * 0.92).roundToDouble(),
        color: color,
      ),
    );
  }
}

/// Custom renderer for fenced code blocks (the Markdown `pre` element).
///
/// flutter_markdown_plus's default `pre` handling wraps the code in a
/// horizontal [SingleChildScrollView] that shrink-wraps to the content width,
/// so short snippets render as narrow boxes. This builder instead draws a
/// [Container] with `width: double.infinity` so the box always spans the full
/// preview width, while a horizontal [SingleChildScrollView] inside still lets
/// long lines scroll.
///
/// Only fenced code blocks are affected — inline `code` is untouched because it
/// is not a `pre` element. flutter_markdown_plus still wraps every `pre`
/// builder's output in an outer Container using the stylesheet's
/// `codeblockDecoration`, so callers must neutralise that to a
/// `const BoxDecoration()` to avoid a double box.
class CodeBlockBuilder extends MarkdownElementBuilder {
  CodeBlockBuilder({required this.textStyle, required this.decoration});

  /// Monospace style for the code text (no background highlight).
  final TextStyle textStyle;

  /// The full-width box decoration (subtle background + rounded border).
  final BoxDecoration decoration;

  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // `textContent` concatenates the code text of the `pre`/`code` subtree.
    // Fenced blocks carry a trailing newline; strip a single one so the box
    // does not render an empty last line.
    var code = element.textContent;
    if (code.endsWith('\n')) {
      code = code.substring(0, code.length - 1);
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: decoration,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(code, style: textStyle),
      ),
    );
  }
}
