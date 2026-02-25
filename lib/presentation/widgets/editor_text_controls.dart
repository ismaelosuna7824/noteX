import 'package:flutter/material.dart';
import '../state/theme_state.dart';

/// Compact font-size and line-height controls styled to blend with
/// the Quill toolbar — flat icon buttons, same color scheme, no backgrounds.
///
/// Set [isMarkdown] to use the markdown-specific settings instead of
/// the notes editor settings.
class EditorTextControls extends StatelessWidget {
  final ThemeState themeState;
  final bool isMarkdown;

  const EditorTextControls({
    super.key,
    required this.themeState,
    this.isMarkdown = false,
  });

  double get _fontSize =>
      isMarkdown ? themeState.markdownFontSize : themeState.editorFontSize;
  double get _lineHeight =>
      isMarkdown ? themeState.markdownLineHeight : themeState.editorLineHeight;

  void _setFontSize(double v) => isMarkdown
      ? themeState.setMarkdownFontSize(v)
      : themeState.setEditorFontSize(v);
  void _setLineHeight(double v) => isMarkdown
      ? themeState.setMarkdownLineHeight(v)
      : themeState.setEditorLineHeight(v);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white70 : Colors.grey.shade700;
    final disabledColor = isDark ? Colors.white24 : Colors.grey.shade300;
    final labelColor = isDark ? Colors.white60 : Colors.grey.shade600;
    final dividerColor = isDark ? Colors.white12 : Colors.grey.shade300;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 1, height: 20, color: dividerColor),
        const SizedBox(width: 2),
        // Font size: − icon value +
        _ToolbarButton(
          icon: Icons.remove_rounded,
          color: _fontSize > 10 ? iconColor : disabledColor,
          onTap: _fontSize > 10 ? () => _setFontSize(_fontSize - 1) : null,
        ),
        _ToolbarLabel(
          icon: Icons.format_size_rounded,
          text: '${_fontSize.toInt()}',
          iconColor: labelColor,
          textColor: labelColor,
        ),
        _ToolbarButton(
          icon: Icons.add_rounded,
          color: _fontSize < 24 ? iconColor : disabledColor,
          onTap: _fontSize < 24 ? () => _setFontSize(_fontSize + 1) : null,
        ),
        const SizedBox(width: 2),
        Container(width: 1, height: 20, color: dividerColor),
        const SizedBox(width: 2),
        // Line height: − icon value +
        _ToolbarButton(
          icon: Icons.remove_rounded,
          color: _lineHeight > 1.0 ? iconColor : disabledColor,
          onTap: _lineHeight > 1.0
              ? () => _setLineHeight(
                  ((_lineHeight - 0.1) * 10).round() / 10)
              : null,
        ),
        _ToolbarLabel(
          icon: Icons.format_line_spacing_rounded,
          text: _lineHeight.toStringAsFixed(1),
          iconColor: labelColor,
          textColor: labelColor,
        ),
        _ToolbarButton(
          icon: Icons.add_rounded,
          color: _lineHeight < 2.5 ? iconColor : disabledColor,
          onTap: _lineHeight < 2.5
              ? () => _setLineHeight(
                  ((_lineHeight + 0.1) * 10).round() / 10)
              : null,
        ),
      ],
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ToolbarButton({
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _ToolbarLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color iconColor;
  final Color textColor;

  const _ToolbarLabel({
    required this.icon,
    required this.text,
    required this.iconColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 2),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
      ],
    );
  }
}
