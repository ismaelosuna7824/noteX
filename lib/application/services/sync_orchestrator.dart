
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/services/sync_service.dart';
import '../../domain/value_objects/sync_status.dart';

/// Application service: Orchestrates bidirectional sync.
///
/// Coordinates between local storage, auth state, and remote sync service.
/// Uses Last Write Wins (LWW) conflict resolution based on updatedAt.
class SyncOrchestrator {
  final NoteRepository _noteRepository;
  final AuthRepository _authRepository;
  final SyncService _syncService;

  bool _isSyncing = false;

  SyncOrchestrator(
    this._noteRepository,
    this._authRepository,
    this._syncService,
  );

  /// Sync only if the user is authenticated and not already syncing.
  Future<void> syncIfAuthenticated() async {
    if (!_authRepository.isAuthenticated) return;
    if (_isSyncing) return;

    final userId = _authRepository.currentUserId;
    if (userId == null) return;

    await performSync(userId);
  }

  /// Perform a full bidirectional sync for the given [userId].
  Future<void> performSync(String userId) async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      // 1. Get all local notes that need syncing
      final pendingNotes =
          await _noteRepository.getBySyncStatus(SyncStatus.pendingSync);

      // 2. Push pending notes to remote
      for (final note in pendingNotes) {
        await _syncService.pushNote(note, userId);
      }

      // 3. Pull remote changes
      final remoteNotes = await _syncService.pullNotes(userId);

      // 4. Merge with LWW conflict resolution
      for (final remoteNote in remoteNotes) {
        final localNote = await _noteRepository.getById(remoteNote.id);

        if (localNote == null) {
          // New remote note — save locally
          await _noteRepository.save(remoteNote.markSynced());
        } else {
          // Conflict resolution: Last Write Wins
          final winner = remoteNote.updatedAt.isAfter(localNote.updatedAt)
              ? remoteNote
              : localNote;
          await _noteRepository.save(winner.markSynced());
        }
      }

      // 5. Mark all pushed notes as synced
      for (final note in pendingNotes) {
        await _noteRepository.save(note.markSynced());
      }
    } catch (e) {
      // Log error but don't crash — offline-first means we can retry later
      // In production, use structured logging
      // ignore: avoid_print
      print('[SyncOrchestrator] Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  bool get isSyncing => _isSyncing;
}
