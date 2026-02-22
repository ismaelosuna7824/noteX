import 'package:flutter/material.dart';

import '../value_objects/sync_status.dart';

/// A project groups time entries under a named, color-coded label.
class Project {
  final String id;
  final String name;
  final int colorValue; // ARGB stored as int (Color.toARGB32())
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String? userId;

  const Project({
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

  /// Factory for creating a new project.
  factory Project.create({
    required String id,
    required String name,
    required int colorValue,
    String? userId,
  }) {
    final now = DateTime.now();
    return Project(
      id: id,
      name: name,
      colorValue: colorValue,
      createdAt: now,
      updatedAt: now,
      version: 1,
      syncStatus: SyncStatus.pendingSync,
      userId: userId,
    );
  }

  Color get color => Color(colorValue);

  /// Whether this project has been soft-deleted.
  bool get isDeleted => deletedAt != null;

  Project copyWith({
    String? name,
    int? colorValue,
    DateTime? updatedAt,
    int? version,
    Object? deletedAt = const _Unset(),
    SyncStatus? syncStatus,
    Object? userId = const _Unset(),
  }) {
    return Project(
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

  Project markPendingSync() {
    return copyWith(
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pendingSync,
    );
  }

  Project markSynced() {
    return copyWith(syncStatus: SyncStatus.synced);
  }

  Project markDeleted() {
    return copyWith(
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pendingSync,
    );
  }

  Project incrementVersion() {
    return copyWith(version: version + 1);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Project && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Project(id: $id, name: $name)';
}

// Private sentinel for nullable copyWith fields.
class _Unset {
  const _Unset();
}
