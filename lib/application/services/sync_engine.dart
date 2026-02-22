import 'dart:async';
import 'dart:math' as math;

import '../../domain/repositories/auth_repository.dart';
import '../../domain/services/connectivity_service.dart';
import '../../domain/services/sync_service.dart';
import '../../domain/value_objects/sync_result.dart';

/// Application service: Orchestrates bidirectional sync.
///
/// Coordinates between auth, connectivity, and the sync adapter.
/// Implements retry with exponential backoff and auto-sync on reconnect.
class SyncEngine {
  final AuthRepository _auth;
  final SyncService _syncService;
  final ConnectivityService _connectivity;

  bool _isSyncing = false;
  Timer? _retryTimer;
  int _retryCount = 0;
  static const _maxRetries = 5;

  StreamSubscription<bool>? _connectivitySub;

  SyncEngine({
    required AuthRepository auth,
    required SyncService syncService,
    required ConnectivityService connectivity,
  })  : _auth = auth,
        _syncService = syncService,
        _connectivity = connectivity;

  bool get isSyncing => _isSyncing;

  /// Start listening to connectivity for auto-sync.
  void startAutoSync() {
    _connectivitySub?.cancel();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((online) {
      if (online && _auth.isAuthenticated) {
        sync();
      }
    });
  }

  /// Stop auto-sync listening.
  void stopAutoSync() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _retryTimer?.cancel();
  }

  /// Perform a full sync cycle: Push → Pull → Update timestamp.
  Future<SyncResult> sync() async {
    if (_isSyncing) return SyncResult.skipped();
    if (!_auth.isAuthenticated) return SyncResult.skipped();
    if (!_connectivity.isOnline) return SyncResult.offline();

    _isSyncing = true;
    try {
      final userId = _auth.currentUserId!;
      final lastSync = await _syncService.getLastSyncedAt(userId);

      // 1. Push local pending changes
      final pushResult =
          await _syncService.pushChanges(userId, since: lastSync);

      // 2. Pull remote changes
      final pullResult =
          await _syncService.pullChanges(userId, since: lastSync);

      // 3. Update last_synced_at
      await _syncService.setLastSyncedAt(userId, DateTime.now().toUtc());

      _retryCount = 0;
      _retryTimer?.cancel();

      return pushResult.merge(pullResult);
    } catch (e) {
      _scheduleRetry();
      return SyncResult.failed(e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  /// Initial sync on first login / new device.
  Future<SyncResult> initialSync() async {
    if (!_auth.isAuthenticated) return SyncResult.skipped();
    if (!_connectivity.isOnline) return SyncResult.offline();

    _isSyncing = true;
    try {
      final userId = _auth.currentUserId!;

      // Push any existing local data first
      final pushResult = await _syncService.pushChanges(userId);

      // Pull everything from remote
      await _syncService.fullPull(userId);

      // Update timestamp
      await _syncService.setLastSyncedAt(userId, DateTime.now().toUtc());

      _retryCount = 0;
      return pushResult;
    } catch (e) {
      return SyncResult.failed(e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  /// Quick sync triggered after a local change (debounced at use-case level).
  Future<void> syncIfAuthenticated() async {
    if (!_auth.isAuthenticated) return;
    if (!_connectivity.isOnline) return;
    await sync();
  }

  /// Retry with exponential backoff.
  void _scheduleRetry() {
    if (_retryCount >= _maxRetries) return;
    final delay = Duration(seconds: math.pow(2, _retryCount).toInt());
    _retryCount++;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => sync());
  }

  void dispose() {
    stopAutoSync();
  }
}
