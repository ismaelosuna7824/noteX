import 'package:flutter/material.dart';

/// One selectable row inside an [AppPickerMenu].
///
/// The default constructor is a real, selectable value — it renders with a
/// leading [icon] (or a coloured [dotColor], e.g. a project's own colour),
/// and shows a check when it is the picker's current [AppPickerMenu.value].
/// [AppPickerOption.action] renders a footer-style action row instead (e.g.
/// "New project…") — always accent-coloured, never shows a check. Its
/// [value] is just a sentinel the caller recognises in its own
/// [AppPickerMenu.onSelected] callback, exactly like every picker already
/// branched on a sentinel value before this widget existed — this widget
/// never interprets [value] itself, only compares it for the check mark.
class AppPickerOption<T> {
  const AppPickerOption({
    required this.value,
    required this.label,
    this.icon,
    this.dotColor,
    this.trailing,
  }) : isAction = false;

  const AppPickerOption.action({
    required this.value,
    required this.label,
    this.icon,
  })  : isAction = true,
        dotColor = null,
        trailing = null;

  final T value;
  final String label;
  final IconData? icon;
  final Color? dotColor;
  final bool isAction;

  /// Optional per-row trailing affordance (e.g. an inline delete icon).
  final Widget? trailing;
}

/// The one shared picker for every "choose one of a short list" control in
/// the task-tracker feature — modelled on the timer page's own project
/// picker (`timer_page.dart`'s `_showProjectMenu`), which already had the
/// qualities every other picker was missing: rounded corners matching the
/// app's own radius, the app's own dark-neutral surface (never the ambient
/// seed-tinted `ColorScheme.fromSeed` default `AlertDialog`/menu defaults
/// resolve to), a leading icon or colour dot per row, and a visible check on
/// the current selection.
///
/// Renders [child] as the trigger (wrapped in a focusable, tappable
/// [InkWell] so Tab reaches it, Enter/Space activates it, and it paints a
/// real focus highlight for keyboard users) and opens a rounded [showMenu]
/// anchored under it on tap or activation.
///
/// Selecting a row calls [onSelected] with that row's own value — the same
/// "raw value out, caller decides what to do with it" shape every converted
/// picker's own `onChanged` already had, so a sentinel action value (like
/// "create a new project") still just flows through unchanged.
///
/// Internally, the menu is keyed by each option's INDEX, not its value —
/// deliberately, so a legitimate `null`-valued option (e.g. "No Project")
/// is never confused with `showMenu` returning `null` for "dismissed
/// without choosing anything" (an ambiguity a raw `showMenu<T>` would
/// otherwise have whenever `T` is nullable).
///
/// [focusNode], when provided, is released right after a selection is
/// applied — the fix for "diagnosed problem #1" (a lingering focus
/// rectangle after a picker's own async focus hand-back once its menu
/// route pops), now built into the shared widget instead of duplicated by
/// every caller. A keyboard user who tabs TO the control afterward is
/// unaffected — the same contract the original per-caller fix documented.
class AppPickerMenu<T> extends StatefulWidget {
  const AppPickerMenu({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
    required this.surfaceColor,
    required this.accentColor,
    required this.child,
    this.focusNode,
    this.minWidth = 160,
    this.enabled = true,
    this.expand = false,
    this.borderRadius,
    this.semanticsLabel,
  });

  /// The picker's current value — compared against each
  /// [AppPickerOption.value] to decide which row shows the check mark.
  final T value;
  final List<AppPickerOption<T>> options;
  final ValueChanged<T> onSelected;

  /// The app's own dark-neutral surface (e.g. `ThemeState.editorBgColor`)
  /// — threaded explicitly, never resolved from the ambient `Theme`, same
  /// convention every dialog in this feature already follows.
  final Color surfaceColor;
  final Color accentColor;

  /// The trigger's visual content — kept entirely caller-defined so this
  /// widget adapts to each existing pill/label style instead of imposing a
  /// new one.
  final Widget child;
  final FocusNode? focusNode;

  /// Minimum width of the opened menu.
  final double minWidth;
  final bool enabled;

  /// When true, the trigger's tappable area stretches to fill the width
  /// available to it (matching a form-field-style picker); when false
  /// (default) it shrink-wraps [child], matching a compact pill trigger.
  final bool expand;

  /// Splash/highlight radius for the trigger itself — independent from the
  /// opened menu's own rounded corners, so each trigger keeps matching its
  /// existing container shape.
  final BorderRadius? borderRadius;
  final String? semanticsLabel;

  @override
  State<AppPickerMenu<T>> createState() => _AppPickerMenuState<T>();
}

class _AppPickerMenuState<T> extends State<AppPickerMenu<T>> {
  static const double _menuRadius = 14;

  Future<void> _open() async {
    if (!widget.enabled) return;
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomLeft(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Color.alphaBlend(
      widget.surfaceColor.withValues(alpha: 0.96),
      isDark ? Colors.black : Colors.white,
    );
    final mutedColor = isDark ? Colors.white70 : Colors.grey.shade800;

    final selectedIndex = await showMenu<int>(
      context: context,
      position: position,
      color: surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(_menuRadius)),
      constraints: BoxConstraints(minWidth: widget.minWidth),
      items: [
        for (var i = 0; i < widget.options.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: _AppPickerRow<T>(
              option: widget.options[i],
              selected: !widget.options[i].isAction &&
                  widget.options[i].value == widget.value,
              mutedColor: mutedColor,
              accentColor: widget.accentColor,
            ),
          ),
      ],
    );

    if (selectedIndex != null) {
      final node = widget.focusNode;
      if (node != null) _suppressFocusReclaim(node);
      widget.onSelected(widget.options[selectedIndex].value);
    }
  }

  /// Reacts to a focus hand-back once the menu route finishes popping —
  /// see [AppPickerMenu]'s own doc for why this is needed at all. For a
  /// short window after a selection, if [node] regains focus, it is
  /// immediately dropped again; the listener removes itself once that
  /// window passes, so it never interferes with a later, legitimate
  /// keyboard/mouse focus on the same control.
  void _suppressFocusReclaim(FocusNode node) {
    void reclaimGuard() {
      if (node.hasFocus) node.unfocus();
    }

    node.addListener(reclaimGuard);
    Future.delayed(const Duration(milliseconds: 500), () {
      node.removeListener(reclaimGuard);
    });
  }

  @override
  Widget build(BuildContext context) {
    final content =
        widget.expand ? SizedBox(width: double.infinity, child: widget.child) : widget.child;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        focusNode: widget.focusNode,
        onTap: widget.enabled ? _open : null,
        borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
        child: Semantics(
          button: true,
          label: widget.semanticsLabel,
          child: content,
        ),
      ),
    );
  }
}

class _AppPickerRow<T> extends StatelessWidget {
  const _AppPickerRow({
    required this.option,
    required this.selected,
    required this.mutedColor,
    required this.accentColor,
  });

  final AppPickerOption<T> option;
  final bool selected;
  final Color mutedColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final color = option.isAction || selected ? accentColor : mutedColor;
    return Row(
      children: [
        // Fixed-width check slot — reserved whether or not this row is
        // selected, so every row's label starts at the same x offset.
        SizedBox(
          width: 18,
          child: selected
              ? Icon(Icons.check_rounded, size: 14, color: accentColor)
              : null,
        ),
        const SizedBox(width: 4),
        if (option.dotColor != null) ...[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: option.dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
        ] else if (option.icon != null) ...[
          Icon(option.icon, size: 16, color: color),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            option.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
                  option.isAction || selected ? FontWeight.w600 : FontWeight.normal,
              color: color,
            ),
          ),
        ),
        if (option.trailing != null) ...[
          const SizedBox(width: 4),
          option.trailing!,
        ],
      ],
    );
  }
}
