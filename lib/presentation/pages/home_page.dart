import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:morphable_shape/morphable_shape.dart';
import '../state/app_state.dart';
import '../state/reminder_state.dart';
import '../state/theme_state.dart';
import '../state/timer_state.dart';

/// Dark-mode card surface — deep navy, slightly transparent so the bg image
/// shows through subtly.
const _kDarkCard = Color(0xFF1A1A2E);

/// Home/Dashboard page.
///
/// Large hero area with background image, bold title text,
/// and organic-shaped cards at the bottom using morphable_shape.
class HomePage extends StatelessWidget {
  final AppState appState;
  final ThemeState themeState;

  const HomePage({
    super.key,
    required this.appState,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = themeState.accentColor;

    // Hero text color computed via WCAG contrast ratio against the background.
    final heroColor = themeState.heroTextColor;
    final isLightText = heroColor.computeLuminance() > 0.5;
    final heroShadows = [
      Shadow(
        color: isLightText
            ? Colors.black.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.4),
        blurRadius: 12,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // Hero typography in top-left
            Positioned(
              left: 32,
              top: 32,
              child: _HeroText(
                heroColor: heroColor,
                theme: theme,
                shadows: heroShadows,
              ),
            ),

            // Pending reminders card (top-right)
            Positioned(
              right: 24,
              top: 16,
              child: _ReminderCard(
                accentColor: accentColor,
                onNavigateToReminders: () => appState.navigateToPage(7),
              ),
            ),

            // Stats & Actions at bottom
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: _buildStatsRow(context, theme, accentColor),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatsRow(
    BuildContext context,
    ThemeData theme,
    Color accentColor,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // "Explore, Write, and ENJOY" organic card (left)
          Expanded(
            flex: 3,
            child: _buildEnjoyCard(context, theme, accentColor, isDark),
          ),

          const SizedBox(width: 16),

          // Combined "Total Notes + Today's Note" organic card (center)
          Expanded(
            flex: 2,
            child: _buildCombinedStatsCard(context, theme, accentColor, isDark),
          ),

          const SizedBox(width: 16),

          // Right column: Daily Tasks card stacked above Pinned Notes card
          Expanded(
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDailyTasksCard(context, theme, accentColor),
                const SizedBox(height: 12),
                _buildPinnedNotesCard(context, theme, accentColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── ENJOY card ─────────────────────────────────────────────────────────────
  Widget _buildEnjoyCard(
    BuildContext context,
    ThemeData theme,
    Color accentColor,
    bool isDark,
  ) {
    final shape = RectangleShapeBorder(
      borderRadius: DynamicBorderRadius.only(
        topLeft: DynamicRadius.circular(Length(28)),
        topRight: DynamicRadius.circular(Length(72)),
        bottomLeft: DynamicRadius.circular(Length(72)),
        bottomRight: DynamicRadius.circular(Length(28)),
      ),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: isDark
            ? _kDarkCard.withValues(alpha: 0.90)
            : Colors.white.withValues(alpha: 0.94),
        shape: shape,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            'Explore, Write, and',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
          Text(
            'ENJOY',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 20),
          _buildActionButton(
            context: context,
            label: 'New Note',
            accentColor: accentColor,
            isDark: isDark,
            onTap: () async {
              await appState.createNewNote();
              appState.navigateToPage(2);
            },
          ),
        ],
      ),
    );
  }

  // ─── Combined Stats card ─────────────────────────────────────────────────────
  Widget _buildCombinedStatsCard(
    BuildContext context,
    ThemeData theme,
    Color accentColor,
    bool isDark,
  ) {
    final shape = RectangleShapeBorder(
      borderRadius: DynamicBorderRadius.only(
        topLeft: DynamicRadius.circular(Length(72)),
        topRight: DynamicRadius.circular(Length(28)),
        bottomLeft: DynamicRadius.circular(Length(28)),
        bottomRight: DynamicRadius.circular(Length(72)),
      ),
    );

    final hasTodayNote = appState.currentNote != null;
    final totalNotes = appState.notes.length;

    final primaryText = isDark ? Colors.white : Colors.black87;
    final secondaryText = isDark ? Colors.white54 : Colors.grey.shade500;
    final dividerColor =
        isDark ? Colors.white.withValues(alpha: 0.10) : Colors.grey.shade100;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: isDark ? _kDarkCard.withValues(alpha: 0.90) : Colors.white,
        shape: shape,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(30, 26, 28, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // ── Total Notes ──────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$totalNotes',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: primaryText,
                    ),
                  ),
                  Text(
                    'Total Notes',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondaryText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.note_alt_rounded,
                  color: accentColor,
                  size: 20,
                ),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(color: dividerColor, thickness: 1),
          ),

          // ── Today's Note ─────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasTodayNote ? '1' : '0',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: primaryText,
                    ),
                  ),
                  Text(
                    "Today's Note",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondaryText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _PressButton(
                onTap: hasTodayNote ? () => appState.navigateToPage(2) : null,
                pressScale: 0.88,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: hasTodayNote
                        ? accentColor.withValues(alpha: 0.15)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.10)
                            : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    hasTodayNote
                        ? Icons.north_east_rounded
                        : Icons.today_rounded,
                    color: hasTodayNote
                        ? accentColor
                        : (isDark ? Colors.white38 : Colors.grey.shade400),
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Daily Tasks card ───────────────────────────────────────────────────────
  Widget _buildDailyTasksCard(
    BuildContext context,
    ThemeData theme,
    Color accentColor,
  ) {
    final shape = RectangleShapeBorder(
      borderRadius: DynamicBorderRadius.only(
        topLeft: DynamicRadius.circular(Length(56)),
        topRight: DynamicRadius.circular(Length(24)),
        bottomLeft: DynamicRadius.circular(Length(24)),
        bottomRight: DynamicRadius.circular(Length(56)),
      ),
    );

    return ListenableBuilder(
      listenable: GetIt.instance<TimerState>(),
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final timerState = GetIt.instance<TimerState>();
        final today = DateTime.now();
        final todayDate = DateTime(today.year, today.month, today.day);
        final taskCount = (timerState.entriesByDay[todayDate] ?? []).length;
        final trackedTime = timerState.dailyTotal(todayDate);
        final hasTime = trackedTime.inSeconds > 0;

        final primaryText = isDark ? Colors.white : Colors.black87;
        final secondaryText = isDark ? Colors.white54 : Colors.grey.shade500;

        return _PressButton(
          onTap: () => appState.navigateToPage(4),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: ShapeDecoration(
              color: isDark ? _kDarkCard.withValues(alpha: 0.90) : Colors.white,
              shape: shape,
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.07),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 22, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$taskCount',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: primaryText,
                      ),
                    ),
                    Text(
                      'Tasks today',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (hasTime) ...[
                      const SizedBox(height: 3),
                      Text(
                        _formatDurationShort(trackedTime),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: accentColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.timer_rounded,
                    color: accentColor,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Pinned Notes card ──────────────────────────────────────────────────────
  Widget _buildPinnedNotesCard(
    BuildContext context,
    ThemeData theme,
    Color accentColor,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final pinnedCount = appState.pinnedNotes.length;

    final shape = RectangleShapeBorder(
      borderRadius: DynamicBorderRadius.only(
        topLeft: DynamicRadius.circular(Length(24)),
        topRight: DynamicRadius.circular(Length(24)),
        bottomLeft: DynamicRadius.circular(Length(56)),
        bottomRight: DynamicRadius.circular(Length(24)),
      ),
    );

    final primaryText = isDark ? Colors.white : Colors.black87;
    final secondaryText = isDark ? Colors.white54 : Colors.grey.shade500;

    return _PressButton(
      onTap: () => appState.navigateToPinnedNotes(),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          color: isDark ? _kDarkCard.withValues(alpha: 0.90) : Colors.white,
          shape: shape,
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.07),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$pinnedCount',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: primaryText,
                      ),
                    ),
                    Text(
                      'Pinned Notes',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.push_pin_rounded,
                    color: accentColor,
                    size: 20,
                  ),
                ),
              ],
            ),

          ],
        ),
      ),
    );
  }

  // ─── New Note action button ─────────────────────────────────────────────────
  Widget _buildActionButton({
    required BuildContext context,
    required String label,
    required Color accentColor,
    required VoidCallback onTap,
    bool isDark = false,
  }) {
    final theme = Theme.of(context);

    return _PressButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.north_east_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Static hero text — two lines of bold display text, no animation.
// ─────────────────────────────────────────────────────────────────────────────

class _HeroText extends StatelessWidget {
  final Color heroColor;
  final ThemeData theme;
  final List<Shadow> shadows;

  const _HeroText({
    required this.heroColor,
    required this.theme,
    required this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'IMMERSE IN',
          style: theme.textTheme.displaySmall?.copyWith(
            color: heroColor,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            shadows: shadows,
          ),
        ),
        Text(
          'YOUR NOTES',
          style: theme.textTheme.displayMedium?.copyWith(
            color: heroColor,
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
            shadows: shadows,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reminder card — top-right on home page, shows pending/overdue reminders.
// Uses the same organic morphable_shape design as other dashboard cards.
// Only visible when there are pending reminders for today or earlier.
// ─────────────────────────────────────────────────────────────────────────────

class _ReminderCard extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onNavigateToReminders;

  const _ReminderCard({
    required this.accentColor,
    required this.onNavigateToReminders,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GetIt.instance<ReminderState>(),
      builder: (context, _) {
        final reminderState = GetIt.instance<ReminderState>();
        if (!reminderState.hasPendingToday) {
          return const SizedBox.shrink();
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final pending = reminderState.pendingToday;
        final theme = Theme.of(context);

        final primaryText = isDark ? Colors.white : Colors.black87;
        final secondaryText = isDark ? Colors.white54 : Colors.grey.shade500;
        final dividerColor = isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.grey.shade100;

        final shape = RectangleShapeBorder(
          borderRadius: DynamicBorderRadius.only(
            topLeft: DynamicRadius.circular(Length(24)),
            topRight: DynamicRadius.circular(Length(56)),
            bottomLeft: DynamicRadius.circular(Length(56)),
            bottomRight: DynamicRadius.circular(Length(24)),
          ),
        );

        return _PressButton(
          onTap: onNavigateToReminders,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280, maxHeight: 260),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: ShapeDecoration(
                color: isDark
                    ? _kDarkCard.withValues(alpha: 0.90)
                    : Colors.white,
                shape: shape,
                shadows: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: isDark ? 0.30 : 0.07),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(24, 18, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${pending.length}',
                            style: theme.textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: primaryText,
                            ),
                          ),
                          Text(
                            'Pending',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondaryText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.notifications_active_rounded,
                          color: accentColor,
                          size: 20,
                        ),
                      ),
                    ],
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Divider(color: dividerColor, thickness: 1),
                  ),

                  // Reminder list
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: pending.length,
                      itemBuilder: (context, index) {
                        final reminder = pending[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: Checkbox(
                                  value: false,
                                  onChanged: (_) {
                                    GetIt.instance<ReminderState>()
                                        .completeReminder(reminder.id);
                                  },
                                  activeColor: accentColor,
                                  side: BorderSide(
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.grey.shade400,
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(4),
                                  ),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  reminder.title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: primaryText,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Press button — wraps any widget in a scale-down animation on tap, giving
// satisfying tactile feedback without relying on InkWell's ink overlay.
// ─────────────────────────────────────────────────────────────────────────────

class _PressButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// How far the widget scales down while pressed (0.94 = 6 % smaller).
  final double pressScale;

  const _PressButton({
    required this.child,
    this.onTap,
    this.pressScale = 0.94,
  });

  @override
  State<_PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<_PressButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.onTap != null
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap!();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressScale : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Duration helpers (shared with timer page style)
// ─────────────────────────────────────────────────────────────────────────────

String _formatDurationShort(Duration d) {
  if (d.inHours > 0) {
    final m = d.inMinutes % 60;
    return m > 0 ? '${d.inHours}h ${m}m' : '${d.inHours}h';
  }
  if (d.inMinutes > 0) {
    return '${d.inMinutes}m';
  }
  return '${d.inSeconds}s';
}
