import 'dart:async';
import 'dart:math' as math;

import '../../domain/repositories/auth_repository.dart';
import '../../domain/services/connectivity_service.dart';
import '../../domain/services/sync_service.dart';
import '../../domain/value_objects/sync_result.dart';
import '../use_cases/index_note_links_use_case.dart';

/// Application service: Orchestrates bidirectional sync.
///
/// Coordinates between auth, connectivity, and the sync adapter.
/// Implements retry with exponential backoff and auto-sync on reconnect.
class SyncEngine {
  final AuthRepository _auth;
  final SyncService _syncService;
  final ConnectivityService _connectivity;
  final IndexNoteLinksUseCase _indexLinks;

  bool _isSyncing = false;
  Timer? _retryTimer;
  int _retryCount = 0;
  static const _maxRetries = 5;

  StreamSubscription<bool>? _connectivitySub;

  SyncEngine({
    required AuthRepository auth,
    required SyncService syncService,
    required ConnectivityService connectivity,
    required IndexNoteLinksUseCase indexLinks,
  })  : _auth = auth,
        _syncService = syncService,
        _connectivity = connectivity,
        _indexLinks = indexLinks;

  /// Rebuilds the note link index after a pull brought new bodies down.
  ///
  /// Notes arriving from another device are written straight through the
  /// repository by the sync adapter, bypassing UpdateNoteUseCase and therefore
  /// its indexing hook — so without this, links authored elsewhere would never
  /// produce backlinks on this device.
  ///
  /// It rebuilds wholesale rather than per note because the adapter reports
  /// only counts, not which notes changed. That is a full re-parse of local
  /// bodies, which is cheap at personal-notes scale and is exactly the
  /// recovery path the index is designed around. If a library ever grows large
  /// enough for this to be felt, the fix is for the adapter to report the ids
  /// it wrote, not to make the index authoritative.
  ///
  /// Failures are swallowed: sync succeeded, and a stale index is recoverable.
  Future<void> _reindexAfterPull(SyncResult pull) async {
    if (pull.pulled <= 0) return;
    await _rebuildIndexQuietly();
  }

  /// Rebuilds the index, never letting its failure fail the sync around it.
  Future<void> _rebuildIndexQuietly() async {
    try {
      await _indexLinks.rebuildAll();
    } catch (_) {
      // Intentionally ignored — the index is derived and rebuildable.
    }
  }

  bool get isSyncing => _isSyncing;

  /// Callback invoked after a successful sync cycle completes.
  /// Wire this to [AppState.refreshNotes] so the UI updates sync icons.
  Future<void> Function()? onSyncComplete;

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

  /// Check if the current user is different from the last synced user.
  /// If so, clear all local data and do a full pull for the new user.
  /// Returns true if a user switch was detected and handled.
  Future<bool> handleUserSwitch() async {
    if (!_auth.isAuthenticated) return false;

    final currentUserId = _auth.currentUserId!;

    // Check who last synced on this device
    final storedUserId = await _syncService.getStoredUserId();

    if (storedUserId == null) {
      // First login on this device — run initial sync (push local + full pull)
      if (_connectivity.isOnline) {
        await initialSync();
      }
      return true;
    }

    if (storedUserId == currentUserId) {
      // Same user — no switch needed, just sync pending changes
      return false;
    }

    // Different user detected — wipe all local data
    await _syncService.clearLocalData();

    // Pull everything for the new user
    if (_connectivity.isOnline) {
      await _syncService.fullPull(currentUserId);
      // clearLocalData wiped the index along with the notes, and a full pull
      // writes bodies straight through the repository, so rebuild from what
      // just landed.
      await _rebuildIndexQuietly();
      await _syncService.setLastSyncedAt(currentUserId, DateTime.now().toUtc());
      await onSyncComplete?.call();
    }

    return true;
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

      // 3. Rebuild link index for bodies that arrived from other devices
      await _reindexAfterPull(pullResult);

      // 4. Update last_synced_at
      await _syncService.setLastSyncedAt(userId, DateTime.now().toUtc());

      _retryCount = 0;
      _retryTimer?.cancel();

      final result = pushResult.merge(pullResult);
      await onSyncComplete?.call();
      return result;
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

      // Bodies just landed straight through the repository — build the link
      // index for them. This is the path a brand new device takes, so without
      // it backlinks would stay empty until the user edited something.
      await _rebuildIndexQuietly();

      // Update timestamp
      await _syncService.setLastSyncedAt(userId, DateTime.now().toUtc());

      _retryCount = 0;
      await onSyncComplete?.call();
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
