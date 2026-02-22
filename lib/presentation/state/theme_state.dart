import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:palette_generator_master/palette_generator_master.dart';
import 'package:path_provider/path_provider.dart';

/// Theme and appearance state with disk persistence.
///
/// All settings are saved to a JSON file on every change and
/// restored on next launch via [loadFromDisk].
class ThemeState extends ChangeNotifier {
  String _fontFamily = 'Poppins';
  String? _backgroundImagePath;
  Color _accentColor = const Color(0xFFFFD54F); // Vibrant yellow/gold default
  bool _isDarkMode = true;

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
    Color(0xFF2D3436), // Dark
    Color(0xFF636E72), // Gray
  ];

  /// Bundled preset background images (from assets/images/).
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

  /// Returns `true` when [path] refers to a bundled asset (not a disk file).
  static bool isAssetImage(String? path) =>
      path != null && path.startsWith('assets/');

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
      _isDarkMode = json['isDarkMode'] as bool? ?? true;
      _dominantLuminance =
          (json['dominantLuminance'] as num?)?.toDouble() ?? 0.15;

      final bgPath = json['backgroundImagePath'] as String?;
      if (bgPath != null) {
        // Asset paths are always valid; file paths need an existence check.
        _backgroundImagePath = isAssetImage(bgPath)
            ? bgPath
            : (File(bgPath).existsSync() ? bgPath : null);
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

  /// Set background image and automatically extract a matching accent color.
  ///
  /// Pass `null` to remove the background. Palette extraction runs async
  /// and will call [notifyListeners] again once the color is ready.
  void setBackgroundImage(String? path) {
    _backgroundImagePath = path;

    // When clearing the image, reset to defaults for the dark gradient bg.
    if (path == null) {
      _dominantLuminance = 0.15;
      _heroTextColor = Colors.white;
      _isPaletteLoading = false;
    } else {
      // Show loading indicator while we extract the palette from the new image.
      _isPaletteLoading = true;
    }

    _saveToDisk();
    notifyListeners();

    if (path != null) {
      _extractAndApplyPalette(path);
    }
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
      _isPaletteLoading = false;
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
