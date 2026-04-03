import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Security state with disk persistence for PIN-based note locking.
///
/// Stores a SHA-256 hash of the PIN (never plaintext).
/// Tracks which individual notes have been unlocked in the current view.
/// Unlocked notes are cleared when navigating away.
class SecurityState extends ChangeNotifier {
  String? _pinHash;
  final Set<String> _unlockedNoteIds = {};

  /// Whether a PIN has been configured.
  bool get hasPin => _pinHash != null;

  /// Check if a specific note has been unlocked this session.
  bool isNoteUnlocked(String noteId) => _unlockedNoteIds.contains(noteId);

  /// Set a new PIN (or change existing one).
  Future<void> setPin(String pin) async {
    _pinHash = _hashPin(pin);
    await _saveToDisk();
    notifyListeners();
  }

  /// Remove the PIN entirely.
  Future<void> removePin() async {
    _pinHash = null;
    _unlockedNoteIds.clear();
    await _saveToDisk();
    notifyListeners();
  }

  /// Verify a PIN attempt for a specific note. Returns true if correct.
  /// On success, marks that note as unlocked.
  bool verifyAndUnlock(String noteId, String pin) {
    if (_pinHash == null) return false;
    final match = _hashPin(pin) == _pinHash;
    if (match) {
      _unlockedNoteIds.add(noteId);
      notifyListeners();
    }
    return match;
  }

  /// Verify PIN without unlocking a specific note (for settings).
  bool verifyPin(String pin) {
    if (_pinHash == null) return false;
    return _hashPin(pin) == _pinHash;
  }

  /// Clear all unlocked notes (called on navigation away).
  void lockAll() {
    _unlockedNoteIds.clear();
    notifyListeners();
  }

  /// Load settings from disk on app startup.
  Future<void> loadFromDisk() async {
    try {
      final file = await _getSettingsFile();
      if (!await file.exists()) return;

      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _pinHash = json['pinHash'] as String?;
    } catch (_) {
      // Keep defaults on corrupt file.
    }
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _getSettingsFile();
      await file.writeAsString(jsonEncode({
        'pinHash': _pinHash,
      }));
    } catch (_) {
      // Best-effort persistence.
    }
  }

  Future<File> _getSettingsFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/notex_security_settings.json');
  }

  String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }
}
