import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../widgets/sidebar.dart';
import '../widgets/top_bar.dart';
import '../widgets/update_banner.dart';
import 'home_page.dart';
import 'note_editor_page.dart';
import 'notes_list_page.dart';
import 'calendar_page.dart';
import 'settings_page.dart';
import 'timer_page.dart';
import 'markdown_page.dart';

/// Corner radius used for the rounded window frame.
const double _kWindowRadius = 14.0;

/// Main application shell — left sidebar + top bar + content area.
///
/// Wraps everything in a [ClipRRect] so the window has rounded corners,
/// and adds a thin draggable title strip with custom window controls.
class AppShell extends StatefulWidget {
  final AppState appState;
  final ThemeState themeState;

  const AppShell({
    super.key,
    required this.appState,
    required this.themeState,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WindowListener {
  bool _isMaximized = false;

  // ── Video background player ─────────────────────────────────────────────
  Player? _bgPlayer;
  VideoController? _bgVideoController;
  String? _currentVideoPath;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximizedState();
    widget.themeState.addListener(_syncVideoPlayer);
    _syncVideoPlayer();
  }

  @override
  void dispose() {
    widget.themeState.removeListener(_syncVideoPlayer);
    _disposeVideoPlayer();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeState != widget.themeState) {
      oldWidget.themeState.removeListener(_syncVideoPlayer);
      widget.themeState.addListener(_syncVideoPlayer);
      _syncVideoPlayer();
    }
  }

  // ── Video player lifecycle ──────────────────────────────────────────────

  /// Create, update, or dispose the background video player based on the
  /// current [ThemeState.backgroundImagePath].
  void _syncVideoPlayer() {
    final path = widget.themeState.backgroundImagePath;
    final isVideo = ThemeState.isVideoFile(path);

    if (!isVideo) {
      // Background is an image or null — dispose any active player.
      if (_bgPlayer != null) {
        _disposeVideoPlayer();
        if (mounted) setState(() {});
      }
      return;
    }

    if (_currentVideoPath != path) {
      // New video selected — (re)create the player.
      _disposeVideoPlayer();
      _currentVideoPath = path;

      final player = Player();
      final controller = VideoController(player);

      player.setPlaylistMode(PlaylistMode.loop);
      player.setVolume(widget.themeState.backgroundVolume * 100);

      // Asset videos use the 'asset:///' URI scheme for media_kit;
      // user-uploaded files use the raw filesystem path.
      final mediaUri =
          ThemeState.isAssetImage(path!) ? 'asset:///$path' : path;
      player.open(Media(mediaUri));

      _bgPlayer = player;
      _bgVideoController = controller;
      if (mounted) setState(() {});
    } else {
      // Same video — just sync volume.
      _bgPlayer?.setVolume(widget.themeState.backgroundVolume * 100);
    }
  }

  void _disposeVideoPlayer() {
    _bgPlayer?.dispose();
    _bgPlayer = null;
    _bgVideoController = null;
    _currentVideoPath = null;
  }

  // ── Window state ────────────────────────────────────────────────────────

  Future<void> _syncMaximizedState() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = maximized);
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_kWindowRadius),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // ── Full-screen background ──────────────────────────────
            Positioned.fill(
              child: _buildBackground(widget.themeState),
            ),

            // ── Palette-loading indicator ───────────────────────────
            // Fades in/out as a thin progress bar at the very top of the
            // window while the accent color is being extracted from the
            // newly selected background image.
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
                    widget.themeState.accentColor.withValues(alpha: 0.85),
                  ),
                  minHeight: 3,
                ),
              ),
            ),

            // ── Main layout ─────────────────────────────────────────
            Column(
              children: [
                // Thin draggable title strip with window controls
                _buildTitleBar(),

                // Sidebar + content
                Expanded(
                  child: Row(
                    children: [
                      Sidebar(
                        selectedIndex: widget.appState.selectedPageIndex,
                        onItemSelected: (index) =>
                            widget.appState.navigateToPage(index),
                        accentColor: widget.themeState.accentColor,
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            ListenableBuilder(
                              listenable: widget.appState,
                              builder: (context, _) => TopBar(
                                appState: widget.appState,
                                themeState: widget.themeState,
                                userName: widget.appState.userName,
                                avatarUrl: widget.appState.userAvatar,
                                onProfileTap: () =>
                                    widget.appState.navigateToPage(6),
                              ),
                            ),
                            // Update banner (slides in when a new version is available)
                            ListenableBuilder(
                              listenable: widget.appState,
                              builder: (context, _) {
                                if (!widget.appState.showUpdateBanner) {
                                  return const SizedBox.shrink();
                                }
                                return UpdateBanner(
                                  update: widget.appState.availableUpdate!,
                                  accentColor: widget.themeState.accentColor,
                                  onDismiss: widget.appState.dismissUpdateBanner,
                                  appState: widget.appState,
                                );
                              },
                            ),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: _buildPage(
                                    widget.appState.selectedPageIndex),
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

  /// Thin strip at the top: full-width drag area + window controls on the right.
  Widget _buildTitleBar() {
    return DragToMoveArea(
      child: SizedBox(
        height: 30,
        child: Row(
          children: [
            const Spacer(),
            _WinButton(
              icon: Icons.remove_rounded,
              tooltip: 'Minimize',
              onTap: () => windowManager.minimize(),
            ),
            _WinButton(
              icon: _isMaximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              tooltip: _isMaximized ? 'Restore' : 'Maximize',
              onTap: _toggleMaximize,
            ),
            _WinButton(
              icon: Icons.close_rounded,
              tooltip: 'Close',
              onTap: () => windowManager.close(),
              isClose: true,
            ),
            const SizedBox(width: 8),
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

    if (ThemeState.isAssetImage(path)) {
      // Bundled preset image
      return Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildDefaultBg(themeState.accentColor),
      );
    }

    // User-uploaded file image
    return Image.file(
      File(path),
      fit: BoxFit.cover,
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

/// Single window control button (minimize / maximize / close).
class _WinButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isClose;

  const _WinButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isClose = false,
  });

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: _hovered
                  ? (widget.isClose
                      ? Colors.red.shade400
                      : Colors.white.withValues(alpha: 0.25))
                  : Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.icon,
              size: 11,
              color: _hovered ? Colors.white : Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}
