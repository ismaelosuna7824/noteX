import 'package:flutter/material.dart';
import '../value_objects/sync_status.dart';

/// Core domain entity representing a project/folder that groups markdown files.
///
/// Separate from the time-tracking Project entity.
class MarkdownProject {
  final String id;
  final String name;
  final int colorValue;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String? userId;

  const MarkdownProject({
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

  factory MarkdownProject.create({
    required String id,
    required String name,
    required int colorValue,
    String? userId,
  }) {
    final now = DateTime.now();
    return MarkdownProject(
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

  MarkdownProject copyWith({
    String? name,
    int? colorValue,
    DateTime? updatedAt,
    int? version,
    Object? deletedAt = const _Unset(),
    SyncStatus? syncStatus,
    Object? userId = const _Unset(),
  }) {
    return MarkdownProject(
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

  MarkdownProject markPendingSync() => copyWith(
        updatedAt: DateTime.now(),
        syncStatus: SyncStatus.pendingSync,
      );

  MarkdownProject markSynced() => copyWith(syncStatus: SyncStatus.synced);

  MarkdownProject markDeleted() => copyWith(
        deletedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        syncStatus: SyncStatus.pendingSync,
      );

  MarkdownProject incrementVersion() => copyWith(version: version + 1);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MarkdownProject && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MarkdownProject(id: $id, name: $name)';
}

class _Unset {
  const _Unset();
}
