import 'package:flutter/material.dart';

/// A project groups time entries under a named, color-coded label.
class Project {
  final String id;
  final String name;
  final int colorValue; // ARGB stored as int (Color.toARGB32())
  final DateTime createdAt;

  const Project({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.createdAt,
  });

  Color get color => Color(colorValue);

  Project copyWith({
    String? name,
    int? colorValue,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Project && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Project(id: $id, name: $name)';
}
