import 'package:flutter/material.dart';
import 'package:morphable_shape/morphable_shape.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';

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
            // Floating typography in top-left
            Positioned(
              left: 32,
              top: 32,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'IMMERSE IN',
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: heroColor,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      shadows: heroShadows,
                    ),
                  ),
                  Text(
                    'YOUR NOTES',
                    style: theme.textTheme.displayMedium?.copyWith(
                      color: heroColor,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      shadows: heroShadows,
                    ),
                  ),
                ],
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "Explore, Write, and ENJOY" organic card (left)
        Expanded(
          flex: 3,
          child: _buildEnjoyCard(context, theme, accentColor),
        ),

        const SizedBox(width: 16),

        // Combined "Total Notes + Today's Note" organic card (center-right)
        Expanded(
          flex: 2,
          child: _buildCombinedStatsCard(context, theme, accentColor),
        ),

        const SizedBox(width: 16),

        // Pinned Notes card (far right)
        Expanded(
          flex: 2,
          child: _buildPinnedNotesCard(context, theme, accentColor),
        ),
      ],
    );
  }

  // ─── ENJOY card ─────────────────────────────────────────────────────────────
  // Organic shape: small topLeft/bottomRight, large topRight/bottomLeft
  Widget _buildEnjoyCard(
    BuildContext context,
    ThemeData theme,
    Color accentColor,
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
        color: Colors.white.withValues(alpha: 0.94),
        shape: shape,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Explore, Write, and',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: Colors.black54,
            ),
          ),
          Text(
            'ENJOY',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 20),
          _buildActionButton(
            context: context,
            label: 'New Note',
            accentColor: accentColor,
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
  // Mirror of ENJOY: large topLeft/bottomRight, small topRight/bottomLeft
  Widget _buildCombinedStatsCard(
    BuildContext context,
    ThemeData theme,
    Color accentColor,
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

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: shape,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      // Extra padding near the large 72px corners (topLeft + bottomRight).
      padding: const EdgeInsets.fromLTRB(30, 26, 28, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    'Total Notes',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade500,
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
            child: Divider(color: Colors.grey.shade100, thickness: 1),
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
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    "Today's Note",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              GestureDetector(
                onTap: hasTodayNote ? () => appState.navigateToPage(2) : null,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: hasTodayNote
                        ? accentColor.withValues(alpha: 0.15)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    hasTodayNote
                        ? Icons.north_east_rounded
                        : Icons.today_rounded,
                    color: hasTodayNote ? accentColor : Colors.grey.shade400,
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

  // ─── Pinned Notes card ──────────────────────────────────────────────────────
  // Symmetric shape: large on all corners (rounded pill-ish)
  Widget _buildPinnedNotesCard(
    BuildContext context,
    ThemeData theme,
    Color accentColor,
  ) {
    final pinnedCount = appState.pinnedNotes.length;

    return GestureDetector(
      onTap: () => appState.navigateToPinnedNotes(),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
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
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'Pinned Notes',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade500,
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

            if (pinnedCount > 0) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Divider(color: Colors.grey.shade100, thickness: 1),
              ),
              // Preview of first pinned note title
              Row(
                children: [
                  Expanded(
                    child: Text(
                      appState.pinnedNotes.first.title.isEmpty
                          ? 'Untitled'
                          : appState.pinnedNotes.first.title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.north_east_rounded,
                    color: accentColor,
                    size: 16,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required String label,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
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
                color: Colors.black87,
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
