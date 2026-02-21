import '../../domain/entities/note.dart';
import '../../domain/services/sync_service.dart';

/// Stub adapter for Firebase/Firestore sync.
///
/// Implements the SyncService port with placeholder logic.
/// Replace with real Firestore calls when Firebase is configured.
class FirebaseSyncAdapter implements SyncService {
  bool _isSyncing = false;

  @override
  bool get isSyncing => _isSyncing;

  @override
  Future<void> pushNote(Note note, String userId) async {
    // TODO: Replace with Firestore write:
    // await FirebaseFirestore.instance
    //     .collection('users')
    //     .doc(userId)
    //     .collection('notes')
    //     .doc(note.id)
    //     .set(noteToMap(note));
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<List<Note>> pullNotes(String userId) async {
    // TODO: Replace with Firestore read:
    // final snapshot = await FirebaseFirestore.instance
    //     .collection('users')
    //     .doc(userId)
    //     .collection('notes')
    //     .get();
    // return snapshot.docs.map((d) => mapToNote(d.data())).toList();
    await Future.delayed(const Duration(milliseconds: 100));
    return [];
  }

  @override
  Future<List<Note>> fullSync(List<Note> localNotes, String userId) async {
    _isSyncing = true;
    try {
      // Push all local notes
      for (final note in localNotes) {
        await pushNote(note, userId);
      }
      // Pull remote notes
      final remoteNotes = await pullNotes(userId);
      return [...localNotes, ...remoteNotes];
    } finally {
      _isSyncing = false;
    }
  }
}
