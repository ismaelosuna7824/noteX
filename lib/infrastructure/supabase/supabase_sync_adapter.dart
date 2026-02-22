import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/note.dart';
import '../../domain/entities/project.dart';
import '../../domain/entities/time_entry.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/repositories/project_repository.dart';
import '../../domain/repositories/time_entry_repository.dart';
import '../../domain/services/sync_service.dart';
import '../../domain/value_objects/sync_result.dart';
import '../../domain/value_objects/sync_status.dart';
import '../local/database.dart';

/// Supabase adapter implementing the SyncService port.
///
/// Handles push/pull for all entity types between Drift and Supabase.
/// Uses optimistic locking via version field.
class SupabaseSyncAdapter implements SyncService {
  final SupabaseClient _supabase;
  final AppDatabase _db;
  final NoteRepository _noteRepo;
  final ProjectRepository _projectRepo;
  final TimeEntryRepository _timeEntryRepo;

  bool _isSyncing = false;

  SupabaseSyncAdapter({
    required SupabaseClient supabase,
    required AppDatabase db,
    required NoteRepository noteRepo,
    required ProjectRepository projectRepo,
    required TimeEntryRepository timeEntryRepo,
  })  : _supabase = supabase,
        _db = db,
        _noteRepo = noteRepo,
        _projectRepo = projectRepo,
        _timeEntryRepo = timeEntryRepo;

  @override
  bool get isSyncing => _isSyncing;

  // ── Push ───────────────────────────────────────────────────────────────────

  @override
  Future<SyncResult> pushChanges(String userId, {DateTime? since}) async {
    _isSyncing = true;
    int pushed = 0;
    int conflicts = 0;
    final errors = <String>[];

    try {
      // Push pending notes
      final pendingNotes = [
        ...await _noteRepo.getBySyncStatus(SyncStatus.pendingSync),
        ...await _noteRepo.getBySyncStatus(SyncStatus.localOnly)
      ];
      for (final note in pendingNotes) {
        try {
          await _pushNote(note.copyWith(userId: userId));
          await _noteRepo.save(note.markSynced());
          pushed++;
        } catch (e) {
          print('====== ERROR PUSHING NOTE: $e ======');
          errors.add('Note ${note.id}: $e');
        }
      }

      // Push pending projects
      final pendingProjects = [
        ...await _projectRepo.getBySyncStatus(SyncStatus.pendingSync),
        ...await _projectRepo.getBySyncStatus(SyncStatus.localOnly)
      ];
      for (final project in pendingProjects) {
        try {
          await _pushProject(project.copyWith(userId: userId));
          await _projectRepo.save(project.markSynced());
          pushed++;
        } catch (e) {
          print('====== ERROR PUSHING PROJECT: $e ======');
          errors.add('Project ${project.id}: $e');
        }
      }

      // Push pending time entries
      final pendingEntries = [
        ...await _timeEntryRepo.getBySyncStatus(SyncStatus.pendingSync),
        ...await _timeEntryRepo.getBySyncStatus(SyncStatus.localOnly)
      ];
      for (final entry in pendingEntries) {
        try {
          await _pushTimeEntry(entry.copyWith(userId: userId));
          await _timeEntryRepo.save(entry.markSynced());
          pushed++;
        } catch (e) {
          print('====== ERROR PUSHING TIME ENTRY: $e ======');
          errors.add('TimeEntry ${entry.id}: $e');
        }
      }

      return SyncResult(
        pushed: pushed,
        conflicts: conflicts,
        errors: errors,
      );
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _pushNote(Note note) async {
    final data = _noteToMap(note);
    await _supabase.from('notes').upsert(data, onConflict: 'id');
  }

  Future<void> _pushProject(Project project) async {
    final data = _projectToMap(project);
    await _supabase.from('projects').upsert(data, onConflict: 'id');
  }

  Future<void> _pushTimeEntry(TimeEntry entry) async {
    final data = _timeEntryToMap(entry);
    await _supabase.from('time_entries').upsert(data, onConflict: 'id');
  }

  // ── Pull ───────────────────────────────────────────────────────────────────

  @override
  Future<SyncResult> pullChanges(String userId, {DateTime? since}) async {
    _isSyncing = true;
    int pulled = 0;
    int conflicts = 0;
    final errors = <String>[];

    try {
      // Pull notes
      final notesData = await _fetchTable('notes', since);
      for (final row in notesData) {
        try {
          final result = await _mergeNote(row);
          if (result) pulled++;
        } catch (e) {
          errors.add('Pull note: $e');
        }
      }

      // Pull projects
      final projectsData = await _fetchTable('projects', since);
      for (final row in projectsData) {
        try {
          final result = await _mergeProject(row);
          if (result) pulled++;
        } catch (e) {
          errors.add('Pull project: $e');
        }
      }

      // Pull time entries
      final entriesData = await _fetchTable('time_entries', since);
      for (final row in entriesData) {
        try {
          final result = await _mergeTimeEntry(row);
          if (result) pulled++;
        } catch (e) {
          errors.add('Pull time entry: $e');
        }
      }

      return SyncResult(
        pulled: pulled,
        conflicts: conflicts,
        errors: errors,
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Helper to fetch data from a Supabase table, optionally filtering by updated_at.
  Future<List<Map<String, dynamic>>> _fetchTable(
      String table, DateTime? since) async {
    if (since != null) {
      return await _supabase
          .from(table)
          .select()
          .gt('updated_at', since.toUtc().toIso8601String());
    }
    return await _supabase.from(table).select();
  }


  @override
  Future<void> fullPull(String userId) async {
    await pullChanges(userId); // No 'since' → pulls everything
  }

  // ── Merge Logic (LWW + Version) ────────────────────────────────────────────

  Future<bool> _mergeNote(Map<String, dynamic> remoteData) async {
    final remote = _mapToNote(remoteData);
    final local = await _noteRepo.getById(remote.id);

    if (local == null) {
      // New note from remote
      await _noteRepo.save(remote.markSynced());
      return true;
    }

    // Version-based conflict resolution
    if (remote.version > local.version) {
      // Remote wins
      await _noteRepo.save(remote.markSynced());
      return true;
    } else if (remote.version == local.version &&
        remote.updatedAt.isAfter(local.updatedAt)) {
      // Same version, LWW
      await _noteRepo.save(remote.markSynced());
      return true;
    }
    // Local wins or already up-to-date
    return false;
  }

  Future<bool> _mergeProject(Map<String, dynamic> remoteData) async {
    final remote = _mapToProject(remoteData);
    final local = await _projectRepo.getById(remote.id);

    if (local == null) {
      await _projectRepo.save(remote.markSynced());
      return true;
    }

    if (remote.version > local.version) {
      await _projectRepo.save(remote.markSynced());
      return true;
    } else if (remote.version == local.version &&
        remote.updatedAt.isAfter(local.updatedAt)) {
      await _projectRepo.save(remote.markSynced());
      return true;
    }
    return false;
  }

  Future<bool> _mergeTimeEntry(Map<String, dynamic> remoteData) async {
    final remote = _mapToTimeEntry(remoteData);
    final local = await _timeEntryRepo.getById(remote.id);

    if (local == null) {
      await _timeEntryRepo.save(remote.markSynced());
      return true;
    }

    if (remote.version > local.version) {
      await _timeEntryRepo.save(remote.markSynced());
      return true;
    } else if (remote.version == local.version &&
        remote.updatedAt.isAfter(local.updatedAt)) {
      await _timeEntryRepo.save(remote.markSynced());
      return true;
    }
    return false;
  }

  // ── Sync Metadata ──────────────────────────────────────────────────────────

  @override
  Future<DateTime?> getLastSyncedAt(String userId) async {
    final row = await (_db.select(_db.syncMetadataEntries)
          ..where((t) =>
              t.userId.equals(userId) & t.entityType.equals('global')))
        .getSingleOrNull();
    return row?.lastSyncedAt;
  }

  @override
  Future<void> setLastSyncedAt(String userId, DateTime timestamp) async {
    await _db.into(_db.syncMetadataEntries).insertOnConflictUpdate(
          SyncMetadataEntriesCompanion.insert(
            userId: userId,
            entityType: 'global',
            lastSyncedAt: timestamp,
          ),
        );
  }

  // ── Serialization ──────────────────────────────────────────────────────────

  Map<String, dynamic> _noteToMap(Note note) => {
        'id': note.id,
        'user_id': note.userId,
        'title': note.title,
        'content': note.content,
        'background_image': note.backgroundImage,
        'theme_id': note.themeId,
        'is_pinned': note.isPinned,
        'created_at': note.createdAt.toUtc().toIso8601String(),
        'updated_at': note.updatedAt.toUtc().toIso8601String(),
        'deleted_at': note.deletedAt?.toUtc().toIso8601String(),
        'version': note.version,
        'sync_status': 'synced',
      };

  Note _mapToNote(Map<String, dynamic> m) => Note(
        id: m['id'] as String,
        title: m['title'] as String? ?? '',
        content: m['content'] as String? ?? '[]',
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
        syncStatus: SyncStatus.synced,
        backgroundImage: m['background_image'] as String?,
        themeId: m['theme_id'] as String?,
        isPinned: m['is_pinned'] as bool? ?? false,
        version: m['version'] as int? ?? 1,
        deletedAt: m['deleted_at'] != null
            ? DateTime.parse(m['deleted_at'] as String)
            : null,
        userId: m['user_id'] as String?,
      );

  Map<String, dynamic> _projectToMap(Project p) => {
        'id': p.id,
        'user_id': p.userId,
        'name': p.name,
        'color_value': p.colorValue,
        'created_at': p.createdAt.toUtc().toIso8601String(),
        'updated_at': p.updatedAt.toUtc().toIso8601String(),
        'deleted_at': p.deletedAt?.toUtc().toIso8601String(),
        'version': p.version,
        'sync_status': 'synced',
      };

  Project _mapToProject(Map<String, dynamic> m) => Project(
        id: m['id'] as String,
        name: m['name'] as String,
        colorValue: m['color_value'] as int,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
        syncStatus: SyncStatus.synced,
        version: m['version'] as int? ?? 1,
        deletedAt: m['deleted_at'] != null
            ? DateTime.parse(m['deleted_at'] as String)
            : null,
        userId: m['user_id'] as String?,
      );

  Map<String, dynamic> _timeEntryToMap(TimeEntry e) => {
        'id': e.id,
        'user_id': e.userId,
        'description': e.description,
        'project_id': e.projectId,
        'start_time': e.startTime.toUtc().toIso8601String(),
        'end_time': e.endTime?.toUtc().toIso8601String(),
        'created_at': e.startTime.toUtc().toIso8601String(),
        'updated_at': e.updatedAt.toUtc().toIso8601String(),
        'deleted_at': e.deletedAt?.toUtc().toIso8601String(),
        'version': e.version,
        'sync_status': 'synced',
      };

  TimeEntry _mapToTimeEntry(Map<String, dynamic> m) => TimeEntry(
        id: m['id'] as String,
        description: m['description'] as String? ?? '',
        projectId: m['project_id'] as String?,
        startTime: DateTime.parse(m['start_time'] as String),
        endTime: m['end_time'] != null
            ? DateTime.parse(m['end_time'] as String)
            : null,
        updatedAt: DateTime.parse(m['updated_at'] as String),
        syncStatus: SyncStatus.synced,
        version: m['version'] as int? ?? 1,
        deletedAt: m['deleted_at'] != null
            ? DateTime.parse(m['deleted_at'] as String)
            : null,
        userId: m['user_id'] as String?,
      );
}
