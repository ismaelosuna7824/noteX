import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:morphable_shape/morphable_shape.dart';
import '../../domain/entities/note.dart';
import '../state/app_state.dart';
import '../state/reminder_state.dart';
import '../state/theme_state.dart';
import '../state/timer_state.dart';
import '../state/writing_stats_state.dart';

/// Home/Dashboard page.
///
/// Large hero area with background image, bold title text,
/// and organic-shaped cards at the bottom using morphable_shape.
/// Elements stagger in with a subtle fade + slide on each visit.
class HomePage extends StatefulWidget {
  final AppState appState;
  final ThemeState themeState;

  const HomePage({super.key, required this.appState, required this.themeState});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _staggerController;

  // Staggered intervals — each element fades/slides in overlapping.
  static const _intervals = [
    Interval(0.0, 0.5, curve: Curves.easeOutCubic), // hero text
    Interval(0.1, 0.6, curve: Curves.easeOutCubic), // reminder card
    Interval(0.25, 0.75, curve: Curves.easeOutCubic), // enjoy card
    Interval(0.35, 0.85, curve: Curves.easeOutCubic), // stats card
    Interval(0.45, 1.0, curve: Curves.easeOutCubic), // right column
    Interval(0.15, 0.65, curve: Curves.easeOutCubic), // recent activity
  ];

  late final List<Animation<double>> _fadeAnims;
  late final List<Animation<Offset>> _slideAnims;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnims = _intervals
        .map((i) => CurvedAnimation(parent: _staggerController, curve: i))
        .toList();

    _slideAnims = _intervals.map((i) {
      return Tween<Offset>(
        begin: const Offset(0, 0.04),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _staggerController, curve: i));
    }).toList();

    _staggerController.forward();
  }

  @override
  void dispose() {
    _staggerController.dispose();
    super.dispose();
  }

  AppState get appState => widget.appState;
  ThemeState get themeState => widget.themeState;

  /// Most recently updated non-empty note (for "Continue writing" card).
  Note? get _mostRecentNote {
    final notes = appState.notes;
    Note? best;
    for (final n in notes) {
      if (n.isEmpty) continue;
      if (best == null || n.updatedAt.isAfter(best.updatedAt)) best = n;
    }
    return best;
  }

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

    final recentNote = _mostRecentNote;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < _mobileBreakpoint;

        return Stack(
          children: [
            // Hero typography in top-left
            Positioned(
              left: isMobile ? 20 : 32,
              top: isMobile ? 20 : 32,
              right: isMobile ? 60 : null, // leave room for reminder
              child: FadeTransition(
                opacity: _fadeAnims[0],
                child: SlideTransition(
                  position: _slideAnims[0],
                  child: _HeroText(
                    heroColor: heroColor,
                    accentColor: accentColor,
                    theme: theme,
                    shadows: heroShadows,
                    compact: isMobile,
                  ),
                ),
              ),
            ),

            // Pending reminders card (top-right)
            Positioned(
              right: isMobile ? 16 : 24,
              top: 16,
              child: FadeTransition(
                opacity: _fadeAnims[1],
                child: SlideTransition(
                  position: _slideAnims[1],
                  child: _ReminderCard(
                    accentColor: accentColor,
                    editorBgColor: themeState.editorBgColor,
                    onNavigateToReminders: () => appState.navigateToPage(7),
                  ),
                ),
              ),
            ),

            // Stats & Actions at bottom (with Continue Writing above)
            Positioned(
              left: isMobile ? 16 : 24,
              right: isMobile ? 16 : 24,
              bottom: isMobile ? 16 : 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (recentNote != null && !isMobile)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12, right: 8),
                      child: FadeTransition(
                        opacity: _fadeAnims[5],
                        child: SlideTransition(
                          position: _slideAnims[5],
                          child: _RecentActivityCard(
                            note: recentNote,
                            heroColor: heroColor,
                            accentColor: accentColor,
                            shadows: heroShadows,
                            onTap: () => appState.selectNote(recentNote),
                          ),
                        ),
                      ),
                    ),
                  _buildStatsRow(context, theme, accentColor),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Breakpoint below which we switch to mobile card layout.
  static const double _mobileBreakpoint = 600;

  Widget _buildStatsRow(
    BuildContext context,
    ThemeData theme,
    Color accentColor,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _mobileBreakpoint) {
          return _buildMobileStats(context, theme, accentColor, isDark);
        }
        return _buildDesktopStats(context, theme, accentColor, isDark);
      },
    );
  }

  /// Desktop layout — original 3-column row.
  Widget _buildDesktopStats(
    BuildContext context,
    ThemeData theme,
    Color accentColor,
    bool isDark,
  ) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // "Explore, Write, and ENJOY" organic card (left)
          Expanded(
            flex: 3,
            child: FadeTransition(
              opacity: _fadeAnims[2],
              child: SlideTransition(
                position: _slideAnims[2],
                child: _buildEnjoyCard(context, theme, accentColor, isDark),
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Combined "Total Notes + Today's Note" organic card (center)
          Expanded(
            flex: 2,
            child: FadeTransition(
              opacity: _fadeAnims[3],
              child: SlideTransition(
                position: _slideAnims[3],
                child: _buildCombinedStatsCard(
                  context,
                  theme,
                  accentColor,
                  isDark,
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Right column: Writing Stats card stacked above Pinned Notes card
          Expanded(
            flex: 2,
            child: FadeTransition(
              opacity: _fadeAnims[4],
              child: SlideTransition(
                position: _slideAnims[4],
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildWritingStatsCard(context, theme, accentColor),
                    const SizedBox(height: 12),
                    _buildPinnedNotesCard(context, theme, accentColor),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Mobile layout — compact enjoy banner + 2×2 stat grid.
  Widget _buildMobileStats(
    BuildContext context,
    ThemeData theme,
    Color accentColor,
    bool isDark,
  ) {
    final totalNotes = appState.notes.length;
    final hasTodayNote = appState.currentNote != null;
    final pinnedCount = appState.pinnedNotes.length;
    final primaryText = isDark ? Colors.white : Colors.black87;
    final secondaryText = isDark ? Colors.white54 : Colors.grey.shade500;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Compact enjoy banner ──
        FadeTransition(
          opacity: _fadeAnims[2],
          child: SlideTransition(
            position: _slideAnims[2],
            child: _buildEnjoyCardMobile(context, theme, accentColor, isDark),
          ),
        ),

        const SizedBox(height: 10),

        // ── 2×2 stat grid ──
        FadeTransition(
          opacity: _fadeAnims[3],
          child: SlideTransition(
            position: _slideAnims[3],
            child: Row(
              children: [
                Expanded(
                  child: _buildMiniStatCard(
                    theme: theme,
                    value: '$totalNotes',
                    label: 'Total Notes',
                    icon: Icons.note_alt_rounded,
                    accentColor: accentColor,
                    isDark: isDark,
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildMiniStatCardWithTimer(
                    context,
                    theme,
                    accentColor,
                    isDark,
                    primaryText,
                    secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        FadeTransition(
          opacity: _fadeAnims[4],
          child: SlideTransition(
            position: _slideAnims[4],
            child: Row(
              children: [
                Expanded(
                  child: _buildMiniStatCard(
                    theme: theme,
                    value: hasTodayNote ? '1' : '0',
                    label: "Today's Note",
                    icon: hasTodayNote
                        ? Icons.north_east_rounded
                        : Icons.today_rounded,
                    accentColor: accentColor,
                    isDark: isDark,
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                    onTap: hasTodayNote
                        ? () => appState.navigateToPage(2)
                        : null,
                    iconActive: hasTodayNote,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildMiniStatCard(
                    theme: theme,
                    value: '$pinnedCount',
                    label: 'Pinned Notes',
                    icon: Icons.push_pin_rounded,
                    accentColor: accentColor,
                    isDark: isDark,
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                    onTap: () => appState.navigateToPinnedNotes(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Compact horizontal enjoy card for mobile.
  Widget _buildEnjoyCardMobile(
    BuildContext context,
    ThemeData theme,
    Color accentColor,
    bool isDark,
  ) {
    final shape = RectangleShapeBorder(
      borderRadius: DynamicBorderRadius.only(
        topLeft: DynamicRadius.circular(Length(24)),
        topRight: DynamicRadius.circular(Length(48)),
        bottomLeft: DynamicRadius.circular(Length(48)),
        bottomRight: DynamicRadius.circular(Length(24)),
      ),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: themeState.editorBgColor.withValues(alpha: isDark ? 0.90 : 0.94),
        shape: shape,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.max,
        children: [
          Text(
            'Explore, Write, and',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
          Text(
            'ENJOY',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 400),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildActionButton(
                context: context,
                label: 'Quick Note',
                accentColor: Colors.amber.shade700,
                isDark: isDark,
                onTap: () async {
                  await appState.createQuickNote();
                  appState.navigateToPage(2);
                },
              ),
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
              _buildImportButton(context, accentColor, isDark),
            ],
          ),
        ],
      ),
    );
  }

  /// Mini stat card used in the mobile 2×2 grid.
  Widget _buildMiniStatCard({
    required ThemeData theme,
    required String value,
    required String label,
    required IconData icon,
    required Color accentColor,
    required bool isDark,
    required Color primaryText,
    required Color secondaryText,
    VoidCallback? onTap,
    bool iconActive = true,
  }) {
    final shape = RectangleShapeBorder(
      borderRadius: DynamicBorderRadius.all(DynamicRadius.circular(Length(22))),
    );

    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: themeState.editorBgColor.withValues(alpha: isDark ? 0.90 : 0.94),
        shape: shape,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: primaryText,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondaryText,
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconActive
                  ? accentColor.withValues(alpha: 0.15)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.grey.shade100),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: iconActive
                  ? accentColor
                  : (isDark ? Colors.white38 : Colors.grey.shade400),
              size: 18,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return _PressButton(onTap: onTap, pressScale: 0.95, child: card);
    }
    return card;
  }

  /// Mini Tasks card for mobile — wraps timer state listener.
  Widget _buildMiniStatCardWithTimer(
    BuildContext context,
    ThemeData theme,
    Color accentColor,
    bool isDark,
    Color primaryText,
    Color secondaryText,
  ) {
    return ListenableBuilder(
      listenable: GetIt.instance<TimerState>(),
      builder: (context, _) {
        final timerState = GetIt.instance<TimerState>();
        final today = DateTime.now();
        final todayDate = DateTime(today.year, today.month, today.day);
        final taskCount = (timerState.entriesByDay[todayDate] ?? []).length;

        return _PressButton(
          onTap: () => appState.navigateToPage(4),
          pressScale: 0.95,
          child: _buildMiniStatCard(
            theme: theme,
            value: '$taskCount',
            label: 'Tasks today',
            icon: Icons.timer_rounded,
            accentColor: accentColor,
            isDark: isDark,
            primaryText: primaryText,
            secondaryText: secondaryText,
          ),
        );
      },
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
        color: themeState.editorBgColor.withValues(alpha: isDark ? 0.90 : 0.94),
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
          const SizedBox(height: 70),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildActionButton(
                context: context,
                label: 'Quick Note',
                accentColor: Colors.amber.shade700,
                isDark: isDark,
                onTap: () async {
                  await appState.createQuickNote();
                  appState.navigateToPage(2);
                },
              ),
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
              _buildImportButton(context, accentColor, isDark),
            ],
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
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.grey.shade100;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: themeState.editorBgColor.withValues(alpha: isDark ? 0.90 : 0.94),
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
        mainAxisAlignment: MainAxisAlignment.center,
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
            padding: const EdgeInsets.symmetric(vertical: 30),
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
              color: themeState.editorBgColor.withValues(
                alpha: isDark ? 0.90 : 0.94,
              ),
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
  Widget _buildWritingStatsCard(
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
      listenable: GetIt.instance<WritingStatsState>(),
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final stats = GetIt.instance<WritingStatsState>();
        final streak = stats.currentStreak;
        final todayWords = stats.todayWordCount;
        final yesterdayWords = stats.yesterdayWordCount;
        final yesterdayNotes = stats.yesterdayNoteCount;
        final weekly = stats.weeklyWordCounts;
        final labels = stats.weeklyLabels;
        final maxWords = weekly.fold<int>(0, (a, b) => a > b ? a : b);

        final primaryText = isDark ? Colors.white : Colors.black87;
        final secondaryText = isDark ? Colors.white54 : Colors.grey.shade500;

        return _PressButton(
          onTap: () => appState.navigateToPage(1),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: ShapeDecoration(
              color: themeState.editorBgColor.withValues(
                alpha: isDark ? 0.90 : 0.94,
              ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Streak row
                Row(
                  children: [
                    Text(
                      streak > 0 ? '🔥' : '✍️',
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        streak > 0 ? '$streak day streak' : 'Start writing!',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: primaryText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$todayWords words',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // Yesterday summary
                Text(
                  yesterdayNotes > 0
                      ? 'Yesterday: $yesterdayNotes note${yesterdayNotes == 1 ? '' : 's'}, $yesterdayWords words'
                      : 'No activity yesterday',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondaryText,
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 12),

                // Mini 7-day bar chart
                SizedBox(
                  height: 32,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(7, (i) {
                      final ratio = maxWords > 0 ? weekly[i] / maxWords : 0.0;
                      final isToday = i == 6;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Tooltip(
                            message: '${labels[i]}: ${weekly[i]} words',
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: FractionallySizedBox(
                                    heightFactor: ratio < 0.05 && weekly[i] > 0
                                        ? 0.05
                                        : ratio,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isToday
                                            ? accentColor
                                            : accentColor.withValues(
                                                alpha: 0.4,
                                              ),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  labels[i],
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: isToday
                                        ? primaryText
                                        : secondaryText,
                                    fontWeight: isToday
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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
          color: themeState.editorBgColor.withValues(
            alpha: isDark ? 0.90 : 0.94,
          ),
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

  Widget _buildImportButton(
    BuildContext context,
    Color accentColor,
    bool isDark,
  ) {
    return _PressButton(
      onTap: () => _showImportDialog(context, accentColor, isDark),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.white,
          shape: BoxShape.circle,
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
        child: Tooltip(
          message: 'Import shared note',
          child: Icon(Icons.download_rounded, color: accentColor, size: 18),
        ),
      ),
    );
  }

  void _showImportDialog(BuildContext context, Color accentColor, bool isDark) {
    final controller = TextEditingController();
    final appState = widget.appState;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import shared note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Paste share link',
            hintText: 'https://...',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) async {
            final url = value.trim();
            if (url.isEmpty) return;
            final title = await appState.importFromShareLink(url);
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    title != null
                        ? 'Imported "$title"'
                        : 'Failed to import. Link may be expired.',
                  ),
                  backgroundColor: title != null ? accentColor : null,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isEmpty) return;
              final title = await appState.importFromShareLink(url);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      title != null
                          ? 'Imported "$title"'
                          : 'Failed to import. Link may be expired.',
                    ),
                    backgroundColor: title != null ? accentColor : null,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero text — gradient display text with periodic shimmer sweep and organic
// accent bar.  The gradient blends heroColor → accentColor; a highlight band
// sweeps across every ~6.5 s.  Shadows are rendered on a separate layer so
// ShaderMask doesn't tint them.
// ─────────────────────────────────────────────────────────────────────────────

class _HeroText extends StatefulWidget {
  final Color heroColor;
  final Color accentColor;
  final ThemeData theme;
  final List<Shadow> shadows;
  final bool compact;

  const _HeroText({
    required this.heroColor,
    required this.accentColor,
    required this.theme,
    required this.shadows,
    this.compact = false,
  });

  @override
  State<_HeroText> createState() => _HeroTextState();
}

class _HeroTextState extends State<_HeroText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;
  Timer? _pauseTimer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _shimmer.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _pauseTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) {
            _shimmer.reset();
            _shimmer.forward();
          }
        });
      }
    });

    // Wait for the stagger entrance to mostly finish before first shimmer.
    _pauseTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) _shimmer.forward();
    });
  }

  @override
  void dispose() {
    _pauseTimer?.cancel();
    _shimmer.dispose();
    super.dispose();
  }

  // ── Shimmer gradient ────────────────────────────────────────────────────

  LinearGradient _buildShimmerGradient() {
    final base = widget.heroColor;
    final isDark = base.computeLuminance() < 0.4;
    final highlight = Color.lerp(
      base,
      widget.accentColor,
      isDark ? 0.65 : 0.5,
    )!;

    // Band sweeps from offscreen-left (-0.2) to offscreen-right (1.2).
    final pos = -0.2 + (_shimmer.value * 1.4);

    // Solid heroColor everywhere except the narrow shimmer band.
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [base, base, highlight, base, base],
      stops: [
        0.0,
        (pos - 0.08).clamp(0.001, 0.999),
        pos.clamp(0.002, 0.998),
        (pos + 0.08).clamp(0.001, 0.999),
        1.0,
      ],
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    final smallStyle =
        (widget.compact
                ? theme.textTheme.headlineMedium
                : theme.textTheme.displaySmall)
            ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 2);
    final mediumStyle =
        (widget.compact
                ? theme.textTheme.headlineLarge
                : theme.textTheme.displayMedium)
            ?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: widget.compact ? 2 : 4,
            );

    // Shared text column builder to avoid duplication.
    Widget textColumn({Color? color, List<Shadow>? shadows}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'IMMERSE IN',
            style: smallStyle?.copyWith(color: color, shadows: shadows),
          ),
          Text(
            'YOUR NOTES',
            style: mediumStyle?.copyWith(color: color, shadows: shadows),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Gradient text with shadow layer ────────────────────────────
        Stack(
          children: [
            // Shadow layer — transparent glyphs, visible shadows.
            textColumn(color: Colors.transparent, shadows: widget.shadows),

            // Gradient + shimmer layer — no shadows.
            AnimatedBuilder(
              animation: _shimmer,
              builder: (context, child) {
                return ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) =>
                      _buildShimmerGradient().createShader(bounds),
                  child: child,
                );
              },
              child: textColumn(color: Colors.white),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // ── Organic accent bar ────────────────────────────────────────
        AnimatedBuilder(
          animation: _shimmer,
          builder: (context, _) {
            final alpha = 0.5 + (_shimmer.value * 0.3);
            return Container(
              width: 52,
              height: 5,
              decoration: BoxDecoration(
                color: widget.accentColor.withValues(alpha: alpha),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(2),
                  topRight: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.accentColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // ── Greeting + date ───────────────────────────────────────────
        Text(
          _greeting(),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: widget.heroColor.withValues(alpha: 0.8),
            fontWeight: FontWeight.w500,
            shadows: widget.shadows,
          ),
        ),

        const SizedBox(height: 6),

        // ── Daily quote ───────────────────────────────────────────────
        Text(
          _dailyQuote(),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: widget.heroColor.withValues(alpha: 0.60),
            fontStyle: FontStyle.italic,
            shadows: widget.shadows,
          ),
        ),
      ],
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _greeting() {
    final now = DateTime.now();
    final hour = now.hour;
    final salute = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    final day = _weekdays[now.weekday - 1];
    final month = _months[now.month - 1];
    return '$salute  ·  $day, $month ${now.day}';
  }

  static const _quotes = [
    'Your ideas matter.',
    'Create something today.',
    'Capture the moment.',
    'Think it. Write it.',
    'Great notes start small.',
    'Let your thoughts flow.',
    'One word at a time.',
    'Write now, edit later.',
    'Ideas need a home.',
    'Your story begins here.',
    'Clarity comes from writing.',
    'Small notes, big ideas.',
    'Write what inspires you.',
    'Every note counts.',
    'Put your mind on paper.',
    'Today is a fresh page.',
    'Notes are seeds of ideas.',
    'Write freely, think deeply.',
    'Your thoughts deserve space.',
    'Start with a single line.',
  ];

  String _dailyQuote() {
    final dayOfYear = DateTime.now()
        .difference(DateTime(DateTime.now().year))
        .inDays;
    return '\u00AB${_quotes[dayOfYear % _quotes.length]}\u00BB';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent activity card — "Continue writing" prompt for the last edited note.
// Compact, semi-transparent, uses heroColor for text so it sits naturally
// over the background image.
// ─────────────────────────────────────────────────────────────────────────────

class _RecentActivityCard extends StatelessWidget {
  final Note note;
  final Color heroColor;
  final Color accentColor;
  final List<Shadow> shadows;
  final VoidCallback onTap;

  const _RecentActivityCard({
    required this.note,
    required this.heroColor,
    required this.accentColor,
    required this.shadows,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeAgo = _formatTimeAgo(note.updatedAt);
    final title = note.title.isNotEmpty ? note.title : 'Untitled';

    final cardBg = heroColor.withValues(alpha: 0.15);
    final cardBorder = heroColor.withValues(alpha: 0.10);
    final labelColor = heroColor.withValues(alpha: 0.70);
    final titleColor = heroColor.withValues(alpha: 0.85);
    final timeColor = heroColor.withValues(alpha: 0.80);

    return _PressButton(
      onTap: onTap,
      child: Container(
        width: 190,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(8),
            bottomLeft: Radius.circular(8),
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(color: cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Continue writing',
              style: theme.textTheme.labelSmall?.copyWith(
                color: labelColor,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
                shadows: shadows,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: titleColor,
                      fontWeight: FontWeight.w700,
                      shadows: shadows,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              timeAgo,
              style: theme.textTheme.bodySmall?.copyWith(
                color: timeColor,
                shadows: shadows,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reminder card — top-right on home page, shows pending/overdue reminders.
// Uses the same organic morphable_shape design as other dashboard cards.
// Only visible when there are pending reminders for today or earlier.
// ─────────────────────────────────────────────────────────────────────────────

class _ReminderCard extends StatelessWidget {
  final Color accentColor;
  final Color editorBgColor;
  final VoidCallback onNavigateToReminders;

  const _ReminderCard({
    required this.accentColor,
    required this.editorBgColor,
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
                color: editorBgColor.withValues(alpha: isDark ? 0.90 : 0.94),
                shape: shape,
                shadows: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.07),
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

                  // Reminder list with staggered entrance
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: pending.length,
                      itemBuilder: (context, index) {
                        final reminder = pending[index];
                        return _HomeReminderItem(
                          key: ValueKey(reminder.id),
                          index: index,
                          reminder: reminder,
                          accentColor: accentColor,
                          isDark: isDark,
                          primaryText: primaryText,
                          onComplete: () {
                            GetIt.instance<ReminderState>().completeReminder(
                              reminder.id,
                            );
                          },
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
// Home reminder item — staggered entrance, hover highlight, animated checkout.
// ─────────────────────────────────────────────────────────────────────────────

class _HomeReminderItem extends StatefulWidget {
  final int index;
  final dynamic reminder;
  final Color accentColor;
  final bool isDark;
  final Color primaryText;
  final VoidCallback onComplete;

  const _HomeReminderItem({
    super.key,
    required this.index,
    required this.reminder,
    required this.accentColor,
    required this.isDark,
    required this.primaryText,
    required this.onComplete,
  });

  @override
  State<_HomeReminderItem> createState() => _HomeReminderItemState();
}

class _HomeReminderItemState extends State<_HomeReminderItem>
    with SingleTickerProviderStateMixin {
  // Completion exit animation
  late final AnimationController _exitController;
  late final Animation<double> _exitOpacity;
  late final Animation<Offset> _exitSlide;

  @override
  void initState() {
    super.initState();

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _exitOpacity = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeIn));
    _exitSlide = Tween<Offset>(begin: Offset.zero, end: const Offset(0.15, 0))
        .animate(
          CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic),
        );
  }

  @override
  void dispose() {
    _exitController.dispose();
    super.dispose();
  }

  void _handleComplete() async {
    await _exitController.forward();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _exitSlide,
      child: FadeTransition(
        opacity: _exitOpacity,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: false,
                  onChanged: (_) => _handleComplete(),
                  activeColor: widget.accentColor,
                  side: BorderSide(
                    color: widget.isDark
                        ? Colors.white38
                        : Colors.grey.shade400,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.reminder.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: widget.primaryText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
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

  const _PressButton({required this.child, this.onTap, this.pressScale = 0.94});

  @override
  State<_PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<_PressButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null
          ? (_) => setState(() => _pressed = true)
          : null,
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
