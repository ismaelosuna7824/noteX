import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../main.dart' show WindowSizeStore;

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
import 'reminder_page.dart';
import 'trash_page.dart';
import 'goodbye_screen.dart';
import '../../injection.dart';
import '../../infrastructure/network/connectivity_adapter.dart';
import '../../domain/services/connectivity_service.dart';
import '../../application/services/sync_engine.dart';

/// Corner radius used for the rounded window frame.
const double _kWindowRadius = 14.0;

/// Main application shell — left sidebar + top bar + content area.
///
/// Wraps everything in a [ClipRRect] so the window has rounded corners,
/// and adds a thin draggable title strip with custom window controls.
class AppShell extends StatefulWidget {
  final AppState appState;
  final ThemeState themeState;

  const AppShell({super.key, required this.appState, required this.themeState});

  @override
  State<AppShell> createState() => _AppShellState();
}

void _noop() {}

class _AppShellState extends State<AppShell> with WindowListener {
  bool _isMaximized = false;

  /// Tracks the previous page index for direction-aware page transitions.
  int _previousPageIndex = 0;

  // ── Compact / sticky note mode ────────────────────────────────────────────
  bool _wasCompactMode = false;
  Size? _fullModeSize;
  bool _isAlwaysOnTop = false;

  // ── Video background player ─────────────────────────────────────────────
  Player? _bgPlayer;
  VideoController? _bgVideoController;
  String? _currentVideoPath;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // Intercept the close event so we can dispose media_kit's native player
    // before the process exits. Without this macOS reports "quit unexpectedly"
    // because libmpv's cleanup is interrupted mid-flight.
    windowManager.setPreventClose(true);
    _syncMaximizedState();
    widget.themeState.addListener(_syncVideoPlayer);
    widget.appState.addListener(_onAppStateChanged);
    _syncVideoPlayer();
    // Sync initial compact mode state (for restored sessions).
    _wasCompactMode = widget.appState.isCompactMode;
    _isAlwaysOnTop = widget.appState.isCompactMode;
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChanged);
    widget.themeState.removeListener(_syncVideoPlayer);
    _disposeVideoPlayer();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowResized() async {
    // Persist window size so it's restored on next launch.
    if (await windowManager.isMaximized()) return;
    final size = await windowManager.getSize();
    if (widget.appState.isCompactMode) {
      WindowSizeStore.saveCompact(size.width, size.height);
    } else {
      WindowSizeStore.save(size.width, size.height);
    }
  }

  @override
  void onWindowClose() async {
    // Show goodbye screen — cleanup runs in parallel with the animation.
    widget.appState.startClosing();

    // Run cleanup tasks while goodbye animates.
    // Persist window size before closing.
    if (!await windowManager.isMaximized()) {
      final size = await windowManager.getSize();
      if (widget.appState.isCompactMode) {
        await WindowSizeStore.saveCompact(size.width, size.height);
      } else {
        await WindowSizeStore.save(size.width, size.height);
      }
    }

    // Persist compact mode state so we can restore on next launch.
    await WindowSizeStore.saveCompactState(
      isCompact: widget.appState.isCompactMode,
      noteId: widget.appState.isCompactMode
          ? widget.appState.currentNote?.id
          : null,
    );

    // Clean up empty notes before closing
    await widget.appState.cleanupEmptyNotes();

    // Push any pending local changes to Supabase before closing.
    await getIt<SyncEngine>().syncIfAuthenticated();

    // Release connectivity listener.
    final connectivity = getIt<ConnectivityService>();
    if (connectivity is ConnectivityAdapter) connectivity.dispose();

    // Stop playback first, then dispose — gives libmpv time to release
    // native resources cleanly instead of crashing on process exit.
    await _bgPlayer?.stop();
    _bgPlayer?.dispose();
    _bgPlayer = null;
    _bgVideoController = null;
    _currentVideoPath = null;

    // Wait for goodbye animation to finish (at least 1.7s total).
    await Future.delayed(const Duration(milliseconds: 1700));

    await windowManager.destroy();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeState != widget.themeState) {
      oldWidget.themeState.removeListener(_syncVideoPlayer);
      widget.themeState.addListener(_syncVideoPlayer);
      _syncVideoPlayer();
    }
    if (oldWidget.appState != widget.appState) {
      oldWidget.appState.removeListener(_onAppStateChanged);
      widget.appState.addListener(_onAppStateChanged);
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
      // Cap decoded resolution to 1920×1080 — saves ~50-70 % RAM vs raw 4K.
      final controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          width: 1920,
          height: 1080,
        ),
      );

      player.setPlaylistMode(PlaylistMode.loop);
      player.setVolume(widget.themeState.backgroundVolume * 100);

      // Asset videos use the 'asset:///' URI scheme for media_kit;
      // user-uploaded files use the raw filesystem path.
      final mediaUri = ThemeState.isAssetImage(path!) ? 'asset:///$path' : path;
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
  void onWindowMaximize() {
    if (widget.appState.isCompactMode) {
      // Prevent maximize in compact mode.
      windowManager.unmaximize();
      return;
    }
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  @override
  void onWindowFocus() {
    // Resume video playback when window regains focus.
    if (_bgPlayer != null && _currentVideoPath != null) {
      _bgPlayer!.play();
    }
  }

  @override
  void onWindowBlur() {
    // Pause video when window loses focus to save CPU.
    _bgPlayer?.pause();
  }

  @override
  void onWindowMinimize() {
    _bgPlayer?.pause();
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  // ── Compact mode transitions ────────────────────────────────────────────

  void _onAppStateChanged() {
    final isCompact = widget.appState.isCompactMode;
    if (isCompact && !_wasCompactMode) {
      _wasCompactMode = true;
      _applyCompactWindow();
    } else if (!isCompact && _wasCompactMode) {
      _wasCompactMode = false;
      _applyFullWindow();
    }
  }

  Future<void> _applyCompactWindow() async {
    // Save current full-mode window size so we can restore later.
    _fullModeSize = await windowManager.getSize();
    await WindowSizeStore.save(_fullModeSize!.width, _fullModeSize!.height);

    // Un-maximize first if needed.
    if (_isMaximized) await windowManager.unmaximize();

    // Lower minimum size and resize to compact dimensions.
    await windowManager.setMinimumSize(const Size(300, 350));
    final compact = await WindowSizeStore.loadCompact();
    final w = compact?['width'] ?? 400.0;
    final h = compact?['height'] ?? 500.0;
    await windowManager.setSize(Size(w, h));

    // Pin on top by default.
    _isAlwaysOnTop = true;
    await windowManager.setAlwaysOnTop(true);
    if (mounted) setState(() {});
  }

  Future<void> _applyFullWindow() async {
    // Persist compact size for next time.
    final compactSize = await windowManager.getSize();
    await WindowSizeStore.saveCompact(compactSize.width, compactSize.height);

    // Unpin from top.
    _isAlwaysOnTop = false;
    await windowManager.setAlwaysOnTop(false);

    // Restore full-mode minimum size and dimensions.
    await windowManager.setMinimumSize(const Size(900, 600));
    final size = _fullModeSize ?? const Size(1280, 900);
    await windowManager.setSize(size);
    if (mounted) setState(() {});
  }

  Future<void> _toggleAlwaysOnTop() async {
    _isAlwaysOnTop = !_isAlwaysOnTop;
    await windowManager.setAlwaysOnTop(_isAlwaysOnTop);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        // F11 toggles zen mode
        if (event.logicalKey == LogicalKeyboardKey.f11) {
          widget.appState.toggleZenMode();
          return KeyEventResult.handled;
        }
        // Escape exits zen mode
        if (event.logicalKey == LogicalKeyboardKey.escape &&
            widget.appState.isZenMode) {
          widget.appState.exitZenMode();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: DragToResizeArea(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kWindowRadius),
        child: widget.appState.isClosing
          ? const GoodbyeScreen(onComplete: _noop)
          : Scaffold(
        backgroundColor: const Color(0xFF0F1120),
        body: Stack(
          children: [
            // ── Full-screen background ──────────────────────────────
            Positioned.fill(
              child: RepaintBoundary(
                child: _buildBackground(widget.themeState),
              ),
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
                  backgroundColor: const Color(0xFF0F1120),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    widget.themeState.accentColor.withValues(alpha: 0.85),
                  ),
                  minHeight: 3,
                ),
              ),
            ),

            // ── Dim overlay for zen mode ───────────────────────────
            if (widget.appState.isZenMode)
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: widget.appState.isZenMode ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  child: Container(color: Colors.black.withValues(alpha: 0.35)),
                ),
              ),

            // ── Main layout ─────────────────────────────────────────
            widget.appState.isZenMode
                ? _buildZenLayout()
                : widget.appState.isCompactMode
                    ? _buildCompactLayout()
                    : _buildFullLayout(),
          ],
        ),
        ),
      ),
    ),
    );
  }

  // ── Zen layout (focus mode) ────────────────────────────────────────────

  Widget _buildZenLayout() {
    return Column(
      children: [
        _buildTitleBar(),
        Expanded(
          child: NoteEditorPage(
            key: const ValueKey('zen-editor'),
            appState: widget.appState,
            themeState: widget.themeState,
            isZenMode: true,
          ),
        ),
      ],
    );
  }

  // ── Full layout (normal mode) ──────────────────────────────────────────

  Widget _buildFullLayout() {
    return Column(
      children: [
        _buildTitleBar(),
        Expanded(
          child: Row(
            children: [
              RepaintBoundary(
                child: Sidebar(
                  selectedIndex: widget.appState.selectedPageIndex,
                  onItemSelected: (index) {
                    setState(
                      () => _previousPageIndex =
                          widget.appState.selectedPageIndex,
                    );
                    widget.appState.navigateToPage(index);
                  },
                  accentColor: widget.themeState.accentColor,
                  editorBgColor: widget.themeState.editorBgColor,
                  sidebarIconColor: widget.themeState.sidebarIconColor,
                ),
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
                        child: _buildPage(
                          widget.appState.selectedPageIndex,
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
    );
  }

  // ── Compact layout (sticky note mode) ──────────────────────────────────

  Widget _buildCompactLayout() {
    return Column(
      children: [
        _buildCompactTitleBar(),
        Expanded(
          child: NoteEditorPage(
            key: const ValueKey('compact-editor'),
            appState: widget.appState,
            themeState: widget.themeState,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactTitleBar() {
    return DragToMoveArea(
      child: SizedBox(
        height: 30,
        child: Row(
          children: [
            const SizedBox(width: 10),
            Icon(
              Icons.sticky_note_2_rounded,
              size: 14,
              color: Colors.white.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.appState.currentNote?.title ?? 'Sticky Note',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Pin on top toggle
            _WinButton(
              icon: _isAlwaysOnTop
                  ? Icons.push_pin_rounded
                  : Icons.push_pin_outlined,
              tooltip: _isAlwaysOnTop ? 'Unpin from top' : 'Pin on top',
              onTap: _toggleAlwaysOnTop,
            ),
            // Restore to full app
            _WinButton(
              icon: Icons.open_in_full_rounded,
              tooltip: 'Full App',
              onTap: () => widget.appState.exitCompactMode(),
            ),
            _WinButton(
              icon: Icons.remove_rounded,
              tooltip: 'Minimize',
              onTap: () => windowManager.minimize(),
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
      case 7:
        return ReminderPage(
          key: const ValueKey('reminders'),
          appState: widget.appState,
          themeState: widget.themeState,
        );
      case 8:
        return TrashPage(
          key: const ValueKey('trash'),
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
              color: _hovered
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}
