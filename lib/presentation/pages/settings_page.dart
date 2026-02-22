import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import 'auth_dialog.dart';

/// Dark-mode card surface — same navy used across the app.
const _kDarkCard = Color(0xFF1A1A2E);

/// Settings page for theme, font, background, and auth management.
///
/// Uses adaptive card design: light white in light mode, dark navy in dark mode.
class SettingsPage extends StatefulWidget {
  final AppState appState;
  final ThemeState themeState;

  const SettingsPage({
    super.key,
    required this.appState,
    required this.themeState,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// Persistent controller for the horizontal preset-image strip.
  /// Kept alive so the Scrollbar always has a valid scroll position.
  final ScrollController _bgScrollController = ScrollController();

  @override
  void dispose() {
    _bgScrollController.dispose();
    super.dispose();
  }

  // Convenience getters to keep build methods tidy.
  AppState get appState => widget.appState;
  ThemeState get themeState => widget.themeState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = themeState.accentColor;

    // Adaptive colors used in inner items (font rows, account box, etc.)
    final innerBg =
        isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.shade50;
    final innerBorder =
        isDark ? Colors.white.withValues(alpha: 0.10) : Colors.grey.shade200;
    final mutedText = isDark ? Colors.white38 : Colors.grey.shade500;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settings',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: themeState.heroTextColor,
              ),
            ),
            const SizedBox(height: 16),

            // Two-column layout: Left = [AccentColor + BgImage], Right = [Font + Account]
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Left column ──────────────────────────────────────
                Expanded(
                  child: Column(
                    children: [
                      // Accent Color
                      _buildSection(
                        context,
                        isDark: isDark,
                        title: 'Accent Color',
                        icon: Icons.palette_rounded,
                        accentColor: accentColor,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: ThemeState.presetColors.map((color) {
                                final isSelected =
                                    themeState.accentColor == color;
                                return InkWell(
                                  onTap: () =>
                                      themeState.setAccentColor(color),
                                  borderRadius: BorderRadius.circular(20),
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 200),
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: isSelected
                                          ? Border.all(
                                              color: Colors.white, width: 3)
                                          : null,
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: color.withValues(
                                                    alpha: 0.5),
                                                blurRadius: 12,
                                                spreadRadius: 2,
                                              )
                                            ]
                                          : null,
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check,
                                            color: Colors.white, size: 18)
                                        : null,
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 10),
                            // Info badge: colors auto-adapt when a bg is chosen
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color:
                                        accentColor.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome_rounded,
                                      size: 13, color: accentColor),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Auto-adapts to your background',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: accentColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Background Image
                      _buildSection(
                        context,
                        isDark: isDark,
                        title: 'Background Image',
                        icon: Icons.image_rounded,
                        accentColor: accentColor,
                        child: _buildBackgroundPicker(context, accentColor),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // ── Right column ─────────────────────────────────────
                Expanded(
                  child: Column(
                    children: [
                      // Font Family
                      _buildSection(
                        context,
                        isDark: isDark,
                        title: 'Font Family',
                        icon: Icons.text_fields_rounded,
                        accentColor: accentColor,
                        child: Column(
                          children: ThemeState.availableFonts.map((font) {
                            final isSelected = themeState.fontFamily == font;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: InkWell(
                                onTap: () => themeState.setFontFamily(font),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? accentColor.withValues(alpha: 0.08)
                                        : innerBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? accentColor
                                          : innerBorder,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        font,
                                        style: TextStyle(
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: isSelected
                                              ? accentColor
                                              : null,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (isSelected)
                                        Icon(Icons.check,
                                            color: accentColor, size: 16),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Account & Sync
                      _buildSection(
                        context,
                        isDark: isDark,
                        title: 'Account & Sync',
                        icon: Icons.cloud_sync_rounded,
                        accentColor: accentColor,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: innerBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: innerBorder),
                              ),
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundColor:
                                        accentColor.withValues(alpha: 0.15),
                                    child: Icon(
                                      appState.isAuthenticated
                                          ? Icons.person_rounded
                                          : Icons.person_outline_rounded,
                                      size: 28,
                                      color: accentColor,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    appState.isAuthenticated
                                        ? 'Hi, ${appState.userName ?? 'User'}'
                                        : 'Not signed in',
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    appState.isAuthenticated
                                        ? 'Notes synced to cloud'
                                        : 'Sign in to sync across devices',
                                    style: TextStyle(
                                        color: mutedText,
                                        fontSize: 12),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width: double.infinity,
                                    child: appState.isAuthenticated
                                        ? OutlinedButton.icon(
                                            onPressed: () =>
                                                appState.signOut(),
                                            icon: const Icon(
                                                Icons.logout_rounded,
                                                size: 16),
                                            label:
                                                const Text('Sign Out'),
                                            style: OutlinedButton.styleFrom(
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 12),
                                            ),
                                          )
                                        : FilledButton.icon(
                                            onPressed: () {
                                              showDialog(
                                                context: context,
                                                builder: (_) => AuthDialog(appState: appState),
                                              );
                                            },
                                            icon: const Icon(
                                                Icons.login_rounded,
                                                size: 16),
                                            label: const Text(
                                                'Sign in / Register'),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: accentColor,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 12),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Dark mode toggle
                            Container(
                              decoration: BoxDecoration(
                                color: innerBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: innerBorder),
                              ),
                              child: SwitchListTile(
                                title: const Text('Dark Mode',
                                    style: TextStyle(fontSize: 14)),
                                subtitle: Text('Toggle dark theme',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: mutedText)),
                                value: themeState.isDarkMode,
                                onChanged: (_) =>
                                    themeState.toggleDarkMode(),
                                activeTrackColor: accentColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Background picker ──────────────────────────────────────────────────────

  Widget _buildBackgroundPicker(BuildContext context, Color accentColor) {
    final currentPath = themeState.backgroundImagePath;
    final isCustom =
        currentPath != null && !ThemeState.isAssetImage(currentPath);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Preset thumbnails (horizontal scroll) ──────────────────
        SizedBox(
          height: 90, // extra 10px for the scrollbar track
          child: ScrollConfiguration(
            // Enable mouse-drag scrolling on desktop
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
              },
            ),
            child: Scrollbar(
              thumbVisibility: true,
              controller: _bgScrollController,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ListView.separated(
                  controller: _bgScrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: ThemeState.presetBackgrounds.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
              // First slot = "No background"
              if (index == 0) {
                final isSelected = currentPath == null;
                return _BgThumbnail(
                  isSelected: isSelected,
                  accentColor: accentColor,
                  onTap: () => themeState.setBackgroundImage(null),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0F1120), Color(0xFF1A1D2E)],
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.hide_image_outlined,
                          color: Colors.white38, size: 22),
                    ),
                  ),
                );
              }

              final assetPath =
                  ThemeState.presetBackgrounds[index - 1];
              final isSelected = currentPath == assetPath;
              return _BgThumbnail(
                isSelected: isSelected,
                accentColor: accentColor,
                onTap: () => themeState.setBackgroundImage(assetPath),
                child: Image.asset(assetPath, fit: BoxFit.cover),
              );
            },
                ),   // ListView.separated
              ),     // Padding
            ),       // Scrollbar
          ),         // ScrollConfiguration
        ),           // SizedBox

        const SizedBox(height: 12),

        // ── Custom upload row ──────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _pickBackgroundImage(context),
                icon: const Icon(Icons.upload_rounded, size: 18),
                label: const Text('Upload Custom'),
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (isCustom) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => themeState.setBackgroundImage(null),
                icon: const Icon(Icons.clear_rounded, size: 18),
                tooltip: 'Remove custom image',
              ),
            ],
          ],
        ),

        // ── Custom image preview ───────────────────────────────────
        if (isCustom) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(currentPath),
              height: 90,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.broken_image_rounded),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Shared section card ────────────────────────────────────────────────────

  Widget _buildSection(
    BuildContext context, {
    required bool isDark,
    required String title,
    required IconData icon,
    required Color accentColor,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? _kDarkCard.withValues(alpha: 0.90)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  // ── File picker ───────────────────────────────────────────────────────────

  Future<void> _pickBackgroundImage(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        themeState.setBackgroundImage(result.files.single.path);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open file picker. Try selecting a preset image instead.'),
          ),
        );
      }
    }
  }
}

// ── Background thumbnail widget ─────────────────────────────────────────────

class _BgThumbnail extends StatelessWidget {
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;
  final Widget child;

  const _BgThumbnail({
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 116,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accentColor : Colors.grey.shade200,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.35),
                    blurRadius: 10,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              // Checkmark overlay when selected
              if (isSelected)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check,
                        color: Colors.white, size: 10),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
