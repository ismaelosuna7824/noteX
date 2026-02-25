import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:palette_generator_master/palette_generator_master.dart';
import 'package:path_provider/path_provider.dart';
import '../../infrastructure/services/background_downloader.dart';

/// Theme and appearance state with disk persistence.
///
/// All settings are saved to a JSON file on every change and
/// restored on next launch via [loadFromDisk].
class ThemeState extends ChangeNotifier {
  String _fontFamily = 'Poppins';
  String? _backgroundImagePath;
  Color _accentColor = const Color(0xFFFFD54F); // Vibrant yellow/gold default
  bool _isDarkMode = false; // Default to light mode on first launch

  /// 0.0 = very dark background, 1.0 = very bright background.
  /// Defaults to dark so text starts white before the first extraction.
  double _dominantLuminance = 0.15;

  /// WCAG-compliant hero text color computed from the background palette.
  /// Defaults to white (for dark backgrounds / no background).
  Color _heroTextColor = Colors.white;

  /// True while the palette extraction is running after a bg change.
  bool _isPaletteLoading = false;

  /// Cancellation token: each new extraction increments this; stale callbacks
  /// compare against the current value and abort if they no longer match.
  int _paletteToken = 0;

  /// Volume for video backgrounds. 0.0 = muted (default), 1.0 = full volume.
  double _backgroundVolume = 0.0;

  /// Editor body font size in logical pixels.
  double _editorFontSize = 15.0;

  /// Editor line height multiplier.
  double _editorLineHeight = 1.6;

  /// Markdown editor font size in logical pixels.
  double _markdownFontSize = 16.0;

  /// Markdown editor line height multiplier.
  double _markdownLineHeight = 1.0;

  // ── Getters ───────────────────────────────────────────────────────────────

  String get fontFamily => _fontFamily;
  String? get backgroundImagePath => _backgroundImagePath;
  Color get accentColor => _accentColor;
  bool get isDarkMode => _isDarkMode;

  /// True while the palette/accent color is being extracted from a new bg.
  bool get isPaletteLoading => _isPaletteLoading;

  /// Best text color for hero titles over the current background.
  /// Computed via WCAG contrast ratio (minimum 4.5:1) for readability.
  Color get heroTextColor => _heroTextColor;

  /// `true` when the home-page hero text should use light (white-ish) color.
  bool get textNeedsLight =>
      _backgroundImagePath == null || _dominantLuminance < 0.5;

  /// Video background volume (0.0 = muted, 1.0 = full).
  double get backgroundVolume => _backgroundVolume;

  /// Editor body text font size (logical pixels).
  double get editorFontSize => _editorFontSize;

  /// Editor line height multiplier (e.g. 1.0, 1.4, 1.6, 2.0).
  double get editorLineHeight => _editorLineHeight;

  /// Markdown editor font size (logical pixels).
  double get markdownFontSize => _markdownFontSize;

  /// Markdown editor line height multiplier.
  double get markdownLineHeight => _markdownLineHeight;

  // ── Static data ───────────────────────────────────────────────────────────

  /// Available font families.
  static const List<String> availableFonts = [
    'Poppins',
    'Inter',
    'Roboto',
    'Outfit',
    'Playfair Display',
    'Source Code Pro',
    'Nunito',
    'Lato',
  ];

  /// Preset accent colors users can pick from.
  static const List<Color> presetColors = [
    Color(0xFFF5A623), // Golden amber
    Color(0xFF6C5CE7), // Purple
    Color(0xFF00B894), // Teal
    Color(0xFFE17055), // Coral
    Color(0xFF0984E3), // Blue
    Color(0xFFE84393), // Pink
    Color(0xFF00CEC9), // Cyan
    Color(0xFFFD79A8), // Light pink
    Color(0xFFA29BFE), // Lavender
    Color(0xFF55EFC4), // Mint
    Color(0xFFFF7675), // Salmon
    Color(0xFFDFE6E9), // Silver
    Color(0xFF2D3436), // Dark
    Color(0xFF636E72), // Gray
  ];

  /// White accent — only available in dark mode.
  static const Color darkModeWhiteAccent = Color(0xFFFFFFFF);

  /// Bundled preset image backgrounds (from assets/images/).
  /// Videos are no longer bundled — see [remoteVideos].
  static const List<String> presetBackgrounds = [
    'assets/images/anime-night-sky-illustration.jpg',
    'assets/images/anime-style-boy-girl-couple-love.jpg',
    'assets/images/anime-style-boy-girl-couple.jpg',
    'assets/images/anime-style-mythical-dragon-creature (1).jpg',
    'assets/images/anime-style-mythical-dragon-creature.jpg',
    'assets/images/fantasy-anime-style-scene.jpg',
    'assets/images/illustration-anime-character-rain.jpg',
    'assets/images/illustration-anime-city (1).jpg',
    'assets/images/illustration-anime-city.jpg',
    'assets/images/japan-background-digital-art.jpg',
    'assets/images/magenta-landscape-with-fantasy-nature.jpg',
    'assets/images/mythical-dragon-beast-anime-style (1).jpg',
    'assets/images/mythical-dragon-beast-anime-style.jpg',
    'assets/images/1311994.jpeg',
    'assets/images/896653.jpg',
    'assets/images/clay-banks-hwLAI5lRhdM-unsplash.jpg',
  ];

  /// Remote video backgrounds — downloaded on demand to the app cache dir.
  /// Hosted on GitHub Releases under the tag `backgrounds-v1`.
  static const List<RemoteBackground> remoteVideos = [
    RemoteBackground(name: 'Japanese Room',       filename: 'vecteezy_ai-generated-japanese-house-room-with-beautiful-nature-view_36627003.mp4'),
    RemoteBackground(name: 'Japanese Village',    filename: 'vecteezy_traditional-japanese-house-street-rainy-old-asian-village_47974312.mp4'),
    RemoteBackground(name: 'Japanese Street',     filename: 'vecteezy_a-serene-street-lined-with-traditional-wooden-houses-under_47072140.mp4'),
    RemoteBackground(name: 'HD Desk UI Ocarina',  filename: 'HD.Desk.UI.Ocarina.mp4'),
    RemoteBackground(name: 'Zelda Sunset',        filename: 'zeldasunsetdeskop4k.mp4'),
    RemoteBackground(name: 'Bump of Chicken',     filename: 'Bump.Of.Chicken.-.Acacia.Pokemon.Gotcha.Jetdarc.8-bit_Chiptune.Remix.mp4'),
    RemoteBackground(name: 'Snow',                filename: 'ffmpeg_260118093337_c82792_60.mp4'),
    RemoteBackground(name: 'In The Snow',         filename: 'inthesnow.2_1.mp4'),
    RemoteBackground(name: 'Night Drive',         filename: '2020-04-11.20-26-21.mp4'),
    RemoteBackground(name: 'City 1080p',          filename: '1920x1080.mp4'),
    RemoteBackground(name: 'Hatsune Miku',        filename: 'hatsune-miku-nier-automata-desktop-wallpaperwaifu.com.mp4'),
    RemoteBackground(name: 'Punklorde',           filename: 'Punklorde_169.mp4'),
    RemoteBackground(name: 'Klee',                filename: 'KleeWP.mp4'),
    RemoteBackground(name: 'May Waterfall',       filename: 'May.waterfall.desk.anim.HD.mp4'),
    RemoteBackground(name: 'Minecraft Aquarium',  filename: 'Minecraft.Soothing.Scenes.Relaxing.Aquarium.mp4'),
    RemoteBackground(name: 'Screen Clean',        filename: 'screenclean.mp4'),
    RemoteBackground(name: 'Totoro Cave',         filename: 'default.mp4'),
    RemoteBackground(name: 'Abstract',            filename: 'a7UX9KlNBdHrbAu94DiX.mp4'),
    RemoteBackground(name: 'Night Drive 2',       filename: '2017-06-21.02-59-31.mp4'),
    RemoteBackground(name: 'Cat',                 filename: 'cat.mp4'),
    RemoteBackground(name: 'Fire',                filename: 'fire.mp4'),
    RemoteBackground(name: 'Minecraft',           filename: 'mc.mp4'),
    RemoteBackground(name: 'No Game No Life',     filename: 'nogame.mp4'),
    RemoteBackground(name: 'SSR',                 filename: 'ssr.mp4'),
    RemoteBackground(name: 'Tree',                filename: 'tree.mp4'),
    RemoteBackground(name: 'Woman 3',             filename: 'woam3.mp4'),
    RemoteBackground(name: 'Woman',               filename: 'woman.mp4'),
    RemoteBackground(name: 'Woman 2',             filename: 'woman2.mp4'),
  ];

  /// Returns `true` when [path] refers to a bundled asset (not a disk file).
  static bool isAssetImage(String? path) =>
      path != null && path.startsWith('assets/');

  /// Video extensions recognized for background playback.
  static const _videoExtensions = {'.mp4', '.webm', '.mov', '.mkv'};

  /// Returns `true` when [path] points to a video file (by extension).
  static bool isVideoFile(String? path) {
    if (path == null) return false;
    final lower = path.toLowerCase();
    return _videoExtensions.any((ext) => lower.endsWith(ext));
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<File> _getSettingsFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/notex_theme_settings.json');
  }

  /// Load saved settings from disk. Called once at startup before [runApp].
  Future<void> loadFromDisk() async {
    try {
      final file = await _getSettingsFile();
      if (!await file.exists()) return;

      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

      _fontFamily = json['fontFamily'] as String? ?? 'Poppins';
      _isDarkMode = json['isDarkMode'] as bool? ?? false;
      _dominantLuminance =
          (json['dominantLuminance'] as num?)?.toDouble() ?? 0.15;
      _backgroundVolume =
          (json['backgroundVolume'] as num?)?.toDouble() ?? 0.0;
      _editorFontSize =
          (json['editorFontSize'] as num?)?.toDouble() ?? 15.0;
      _editorLineHeight =
          (json['editorLineHeight'] as num?)?.toDouble() ?? 1.6;
      _markdownFontSize =
          (json['markdownFontSize'] as num?)?.toDouble() ?? 16.0;
      _markdownLineHeight =
          (json['markdownLineHeight'] as num?)?.toDouble() ?? 1.0;

      final bgPath = json['backgroundImagePath'] as String?;
      if (bgPath != null) {
        if (isAssetImage(bgPath) && isVideoFile(bgPath)) {
          // Videos are no longer bundled assets — clear stored path so the
          // default image is used instead (migration from pre-1.14 settings).
          _backgroundImagePath = null;
        } else if (isAssetImage(bgPath)) {
          // Bundled images are always valid.
          _backgroundImagePath = bgPath;
        } else {
          // User file or downloaded video — check it still exists on disk.
          _backgroundImagePath =
              File(bgPath).existsSync() ? bgPath : null;
        }
      }

      final colorValue = json['accentColor'] as int?;
      if (colorValue != null) _accentColor = Color(colorValue);

      final heroColorValue = json['heroTextColor'] as int?;
      if (heroColorValue != null) _heroTextColor = Color(heroColorValue);
    } catch (_) {
      // Keep defaults — never crash on a corrupt settings file.
    }

    // First launch: no saved background → use the clay-banks photo as default.
    if (_backgroundImagePath == null) {
      _backgroundImagePath = 'assets/images/clay-banks-hwLAI5lRhdM-unsplash.jpg';
      _isPaletteLoading = true;
      // Persist immediately so the image is remembered even if palette
      // extraction fails (e.g. on macOS release builds).
      await _saveToDisk();
      notifyListeners();
      // Extract palette async — sets accent color + clears _isPaletteLoading.
      _extractAndApplyPalette(_backgroundImagePath!);
    } else {
      notifyListeners();
    }
  }

  /// Write current settings to disk (called after every change).
  Future<void> _saveToDisk() async {
    try {
      final file = await _getSettingsFile();
      await file.writeAsString(jsonEncode({
        'fontFamily': _fontFamily,
        'isDarkMode': _isDarkMode,
        'backgroundImagePath': _backgroundImagePath,
        'accentColor': _accentColor.toARGB32(),
        'dominantLuminance': _dominantLuminance,
        'heroTextColor': _heroTextColor.toARGB32(),
        'backgroundVolume': _backgroundVolume,
        'editorFontSize': _editorFontSize,
        'editorLineHeight': _editorLineHeight,
        'markdownFontSize': _markdownFontSize,
        'markdownLineHeight': _markdownLineHeight,
      }));
    } catch (_) {
      // Silently ignore — UI should never break on a save failure.
    }
  }

  // ── Setters ───────────────────────────────────────────────────────────────

  /// Change the font family and persist.
  void setFontFamily(String family) {
    _fontFamily = family;
    _saveToDisk();
    notifyListeners();
  }

  /// Set background image/video and automatically extract a matching accent color.
  ///
  /// Pass `null` to remove the background. For images, palette extraction runs
  /// async. For videos, dark defaults are applied immediately.
  void setBackgroundImage(String? path) {
    _backgroundImagePath = path;

    // When clearing the background, reset to defaults for the dark gradient.
    if (path == null) {
      _dominantLuminance = 0.15;
      _heroTextColor = Colors.white;
      _isPaletteLoading = false;
    } else if (isVideoFile(path)) {
      // Videos: use dark defaults (no palette extraction from video frames).
      _dominantLuminance = 0.15;
      _heroTextColor = Colors.white;
      _isPaletteLoading = false;
    } else {
      // Images: show loading indicator while we extract the palette.
      _isPaletteLoading = true;
    }

    _saveToDisk();
    notifyListeners();

    // Only extract palette for actual image files, not videos.
    if (path != null && !isVideoFile(path)) {
      _extractAndApplyPalette(path);
    }
  }

  /// Set the video background volume and persist.
  void setBackgroundVolume(double volume) {
    _backgroundVolume = volume.clamp(0.0, 1.0);
    _saveToDisk();
    notifyListeners();
  }

  /// Set the editor font size and persist.
  void setEditorFontSize(double size) {
    _editorFontSize = size.clamp(10.0, 24.0);
    _saveToDisk();
    notifyListeners();
  }

  /// Set the editor line height and persist.
  void setEditorLineHeight(double height) {
    _editorLineHeight = height.clamp(1.0, 2.5);
    _saveToDisk();
    notifyListeners();
  }

  /// Set the markdown editor font size and persist.
  void setMarkdownFontSize(double size) {
    _markdownFontSize = size.clamp(10.0, 24.0);
    _saveToDisk();
    notifyListeners();
  }

  /// Set the markdown editor line height and persist.
  void setMarkdownLineHeight(double height) {
    _markdownLineHeight = height.clamp(1.0, 2.5);
    _saveToDisk();
    notifyListeners();
  }

  /// Extracts the most vibrant color + the dominant luminance from [imagePath].
  ///
  /// Uses a token to silently discard results from previous (stale) calls when
  /// the user switches images rapidly. Safe for both asset and file paths.
  Future<void> _extractAndApplyPalette(String imagePath) async {
    final token = ++_paletteToken;

    try {
      final ImageProvider provider = isAssetImage(imagePath)
          ? AssetImage(imagePath)
          : FileImage(File(imagePath));

      final palette = await PaletteGeneratorMaster.fromImageProvider(
        provider,
        maximumColorCount: 16,
        colorSpace: ColorSpace.rgb,
      );

      // Abort if the user already picked a different image.
      if (token != _paletteToken) return;

      // Dominant luminance for deciding hero-text brightness.
      final dominant = palette.dominantColor?.color ??
          palette.darkMutedColor?.color ??
          palette.lightMutedColor?.color;
      if (dominant != null) {
        _dominantLuminance = dominant.computeLuminance();
        _heroTextColor = palette.getBestTextColorFor(
          dominant,
          minimumContrast: 4.5,
        );
      }

      // Accent color: prefer vibrant, then light-vibrant, then dominant.
      final extracted = palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.dominantColor?.color;

      if (extracted != null) {
        _accentColor = extracted;
      }

      _isPaletteLoading = false;
      await _saveToDisk();
      notifyListeners();
    } catch (_) {
      // Palette extraction is best-effort — never break the UI.
      // Still save to disk so the background image path is persisted even
      // when extraction fails (prevents infinite retry on next launch).
      _isPaletteLoading = false;
      await _saveToDisk();
      notifyListeners();
    }
  }

  /// Change the accent/theme color and persist.
  void setAccentColor(Color color) {
    _accentColor = color;
    _saveToDisk();
    notifyListeners();
  }

  /// Toggle dark mode and persist.
  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    _saveToDisk();
    notifyListeners();
  }

  /// Build the [ThemeData] from current state.
  ThemeData buildTheme() {
    final textTheme = GoogleFonts.getTextTheme(_fontFamily);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _accentColor,
      brightness: _isDarkMode ? Brightness.dark : Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme.apply(
        bodyColor: _isDarkMode ? Colors.white : const Color(0xFF2D3436),
        displayColor: _isDarkMode ? Colors.white : const Color(0xFF2D3436),
      ),
      scaffoldBackgroundColor:
          _isDarkMode ? const Color(0xFF1A1A2E) : const Color(0xFFF8F9FA),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _isDarkMode
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    );
  }
}
