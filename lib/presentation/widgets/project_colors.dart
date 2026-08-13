import 'package:flutter/material.dart';

/// Preset color palette offered when creating a new project.
///
/// Shared by every "New Project" entry point — the timer page's project
/// chip menu and the task detail dialog's project selector — so a project
/// created from either surface offers the identical palette rather than
/// two independently-maintained lists drifting apart.
const List<Color> kProjectColors = [
  Color(0xFF6C5CE7), // Purple
  Color(0xFF0984E3), // Blue
  Color(0xFF00B894), // Teal
  Color(0xFFE17055), // Coral
  Color(0xFFF5A623), // Amber
  Color(0xFFE84393), // Pink
  Color(0xFF2D3436), // Dark
  Color(0xFF00CEC9), // Cyan
  Color(0xFFD63031), // Red
  Color(0xFF6AB04C), // Green
];
