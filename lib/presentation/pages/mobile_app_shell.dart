import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../../injection.dart';
import '../../infrastructure/network/connectivity_adapter.dart';
import '../../domain/services/connectivity_service.dart';
import '../../application/services/sync_engine.dart';
import 'home_page.dart';
import 'note_editor_page.dart';
import 'notes_list_page.dart';
import 'calendar_page.dart';
import 'settings_page.dart';
import 'timer_page.dart';
import 'markdown_page.dart';
import 'reminder_page.dart';

/// Mobile application shell — bottom navigation + content area.
///
/// Replaces [AppShell] on Android and iOS. No window management, no custom
/// title bar, no compact/sticky note mode. Uses [WidgetsBindingObserver] for
/// lifecycle cleanup instead of [WindowListener].
class MobileAppShell extends StatefulWidget {
  final AppState appState;
  final ThemeState themeState;

  const MobileAppShell({
    super.key,
    required this.appState,
    required this.themeState,
  });

  @override
  State<MobileAppShell> createState() => _MobileAppShellState();
}

class _MobileAppShellState extends State<MobileAppShell>
    with WidgetsBindingObserver {
  /// Tracks the previous page index for direction-aware page transitions.
  int _previousPageIndex = 0;

  // ── Video background player ─────────────────────────────────────────────
  Player? _bgPlayer;
  VideoController? _bgVideoController;
  String? _currentVideoPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.themeState.addListener(_syncVideoPlayer);
    _syncVideoPlayer();
  }

  @override
  void dispose() {
    widget.themeState.removeListener(_syncVideoPlayer);
    _disposeVideoPlayer();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _bgPlayer?.pause();
        break;
      case AppLifecycleState.resumed:
        if (_bgPlayer != null && _currentVideoPath != null) {
          _bgPlayer!.play();
        }
        break;
      case AppLifecycleState.detached:
        _onAppDetached();
        break;
      default:
        break;
    }
  }

  Future<void> _onAppDetached() async {
    // Clean up empty notes before closing
    await widget.appState.cleanupEmptyNotes();

    // Push any pending local changes to Supabase.
    await getIt<SyncEngine>().syncIfAuthenticated();

    // Release connectivity listener.
    final connectivity = getIt<ConnectivityService>();
    if (connectivity is ConnectivityAdapter) connectivity.dispose();

    // Clean up video player.
    await _bgPlayer?.stop();
    _bgPlayer?.dispose();
    _bgPlayer = null;
    _bgVideoController = null;
    _currentVideoPath = null;
  }

  @override
  void didUpdateWidget(covariant MobileAppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeState != widget.themeState) {
      oldWidget.themeState.removeListener(_syncVideoPlayer);
      widget.themeState.addListener(_syncVideoPlayer);
      _syncVideoPlayer();
    }
  }

  // ── Video player lifecycle ──────────────────────────────────────────────

  void _syncVideoPlayer() {
    final path = widget.themeState.backgroundImagePath;
    final isVideo = ThemeState.isVideoFile(path);

    if (!isVideo) {
      if (_bgPlayer != null) {
        _disposeVideoPlayer();
        if (mounted) setState(() {});
      }
      return;
    }

    if (_currentVideoPath != path) {
      _disposeVideoPlayer();
      _currentVideoPath = path;

      final player = Player();
      final controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          width: 1920,
          height: 1080,
        ),
      );

      player.setPlaylistMode(PlaylistMode.loop);
      player.setVolume(widget.themeState.backgroundVolume * 100);

      final mediaUri =
          ThemeState.isAssetImage(path!) ? 'asset:///$path' : path;
      player.open(Media(mediaUri));

      _bgPlayer = player;
      _bgVideoController = controller;
      if (mounted) setState(() {});
    } else {
      _bgPlayer?.setVolume(widget.themeState.backgroundVolume * 100);
    }
  }

  void _disposeVideoPlayer() {
    _bgPlayer?.dispose();
    _bgPlayer = null;
    _bgVideoController = null;
    _currentVideoPath = null;
  }

  // ── Bottom navigation mapping ───────────────────────────────────────────
  // Sidebar indices: 0=Home, 1=Notes, 2=Editor, 3=Calendar, 4=Timer,
  //                  5=Markdown, 6=Settings, 7=Reminders
  // Bottom nav uses a compact 5-item bar with the most-used features.
  // Settings and Reminders are accessible from the "More" overflow or
  // directly via their page indices.

  static const _navDestinations = [
    (0, Icons.home_rounded, 'Home'),
    (1, Icons.list_alt_rounded, 'Notes'),
    (2, Icons.edit_note_rounded, 'Editor'),
    (3, Icons.calendar_month_rounded, 'Calendar'),
    (4, Icons.timer_rounded, 'Timer'),
    (5, Icons.article_rounded, 'Markdown'),
    (6, Icons.settings_rounded, 'Settings'),
    (7, Icons.notifications_rounded, 'Reminders'),
  ];

  int get _bottomNavIndex {
    final pageIndex = widget.appState.selectedPageIndex;
    final navIdx = _navDestinations.indexWhere((d) => d.$1 == pageIndex);
    return navIdx >= 0 ? navIdx : 0;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.appState, widget.themeState]),
      builder: (context, _) {
        final accent = widget.themeState.accentColor;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        final navIndex = _bottomNavIndex;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // ── Full-screen background ─────────────────────────────
              Positioned.fill(
                child: RepaintBoundary(
                  child: _buildBackground(widget.themeState),
                ),
              ),

              // ── Palette-loading indicator ──────────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: widget.themeState.isPaletteLoading ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 350),
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      accent.withValues(alpha: 0.85),
                    ),
                    minHeight: 3,
                  ),
                ),
              ),

              // ── Content area with SafeArea ─────────────────────────
              SafeArea(
                bottom: false,
                child: Padding(
                  // Leave space for the floating nav bar + safe area
                  padding: EdgeInsets.only(
                    bottom: 70 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) {
                      final isForward =
                          widget.appState.selectedPageIndex >=
                              _previousPageIndex;
                      final slide = Tween<Offset>(
                        begin: Offset(0, isForward ? 0.03 : -0.03),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ));
                      return SlideTransition(
                        position: slide,
                        child: FadeTransition(
                          opacity: CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeIn,
                          ),
                          child: child,
                        ),
                      );
                    },
                    child: _buildPage(widget.appState.selectedPageIndex),
                  ),
                ),
              ),

              // ── Floating glassmorphic nav bar ──────────────────────
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).padding.bottom + 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      height: 58,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.45)
                            : Colors.white.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.06),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                                alpha: isDark ? 0.35 : 0.10),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (int i = 0;
                              i < _navDestinations.length;
                              i++)
                            _buildNavItem(
                              icon: _navDestinations[i].$2,
                              label: _navDestinations[i].$3,
                              isSelected: i == navIndex,
                              accentColor: accent,
                              isDark: isDark,
                              onTap: () {
                                final pageIndex =
                                    _navDestinations[i].$1;
                                setState(() => _previousPageIndex =
                                    widget.appState.selectedPageIndex);
                                widget.appState
                                    .navigateToPage(pageIndex);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color accentColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected
                    ? accentColor.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 22,
                color: isSelected
                    ? accentColor
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.5)
                        : Colors.black.withValues(alpha: 0.4)),
              ),
            ),
            // Accent dot indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(top: 3),
              width: isSelected ? 5 : 0,
              height: isSelected ? 5 : 0,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return HomePage(
          key: const ValueKey('home'),
          appState: widget.appState,
          themeState: widget.themeState,
        );
      case 1:
        return NotesListPage(
          key: const ValueKey('notes'),
          appState: widget.appState,
          themeState: widget.themeState,
        );
      case 2:
        return NoteEditorPage(
          key: const ValueKey('editor'),
          appState: widget.appState,
          themeState: widget.themeState,
        );
      case 3:
        return CalendarPage(
          key: const ValueKey('calendar'),
          appState: widget.appState,
          themeState: widget.themeState,
        );
      case 4:
        return TimerPage(
          key: const ValueKey('timer'),
          appState: widget.appState,
          themeState: widget.themeState,
        );
      case 5:
        return MarkdownPage(
          key: const ValueKey('markdown'),
          appState: widget.appState,
          themeState: widget.themeState,
        );
      case 6:
        return SettingsPage(
          key: const ValueKey('settings'),
          appState: widget.appState,
          themeState: widget.themeState,
        );
      case 7:
        return ReminderPage(
          key: const ValueKey('reminders'),
          appState: widget.appState,
          themeState: widget.themeState,
        );
      default:
        return HomePage(
          key: const ValueKey('home'),
          appState: widget.appState,
          themeState: widget.themeState,
        );
    }
  }

  /// Renders the full-bleed background: video, asset image, file image, or gradient.
  Widget _buildBackground(ThemeState themeState) {
    final path = themeState.backgroundImagePath;
    if (path == null) return _buildDefaultBg(themeState.accentColor);

    // Video background
    if (ThemeState.isVideoFile(path) && _bgVideoController != null) {
      return Video(
        controller: _bgVideoController!,
        fit: BoxFit.cover,
        controls: NoVideoControls,
        fill: Colors.black,
      );
    }

    // Cap decoded resolution to 1920px wide — saves ~70 % RAM vs raw 4K.
    if (ThemeState.isAssetImage(path)) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        cacheWidth: 1920,
        errorBuilder: (_, _, _) => _buildDefaultBg(themeState.accentColor),
      );
    }

    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: 1920,
      errorBuilder: (_, _, _) => _buildDefaultBg(themeState.accentColor),
    );
  }

  Widget _buildDefaultBg(Color accentColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0F1120),
            const Color(0xFF1A1D2E),
            Color.lerp(const Color(0xFF1A1D2E), accentColor, 0.15)!,
          ],
        ),
      ),
    );
  }
}
