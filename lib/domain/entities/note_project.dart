import 'package:flutter/material.dart';
import '../value_objects/sync_status.dart';

/// Core domain entity representing a project/folder that groups notes.
///
/// Separate from the time-tracking Project and MarkdownProject entities.
class NoteProject {
  final String id;
  final String name;
  final int colorValue;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String? userId;

  const NoteProject({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.createdAt,
    required this.updatedAt,
    this.version = 1,
    this.deletedAt,
    this.syncStatus = SyncStatus.localOnly,
    this.userId,
  });

  factory NoteProject.create({
    required String id,
    required String name,
    required int colorValue,
    String? userId,
  }) {
    final now = DateTime.now();
    return NoteProject(
      id: id,
      name: name,
      colorValue: colorValue,
      createdAt: now,
      updatedAt: now,
      version: 1,
      syncStatus: SyncStatus.localOnly,
      userId: userId,
    );
  }

  Color get color => Color(colorValue);
  bool get isDeleted => deletedAt != null;

  NoteProject copyWith({
    String? name,
    int? colorValue,
    DateTime? updatedAt,
    int? version,
    Object? deletedAt = const _Unset(),
    SyncStatus? syncStatus,
    Object? userId = const _Unset(),
  }) {
    return NoteProject(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      deletedAt: deletedAt is _Unset ? this.deletedAt : deletedAt as DateTime?,
      syncStatus: syncStatus ?? this.syncStatus,
      userId: userId is _Unset ? this.userId : userId as String?,
    );
  }

  NoteProject markPendingSync() => copyWith(
        updatedAt: DateTime.now(),
        syncStatus: SyncStatus.pendingSync,
      );

  NoteProject markSynced() => copyWith(syncStatus: SyncStatus.synced);

  NoteProject markDeleted() => copyWith(
        deletedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        syncStatus: SyncStatus.pendingSync,
      );

  NoteProject incrementVersion() => copyWith(version: version + 1);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NoteProject && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'NoteProject(id: $id, name: $name)';
}

class _Unset {
  const _Unset();
}
