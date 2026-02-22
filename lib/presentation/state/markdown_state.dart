import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/markdown_file.dart';
import '../../domain/entities/markdown_project.dart';
import '../../application/use_cases/markdown/create_markdown_file_use_case.dart';
import '../../application/use_cases/markdown/get_markdown_files_use_case.dart';
import '../../application/use_cases/markdown/update_markdown_file_use_case.dart';
import '../../application/use_cases/markdown/delete_markdown_file_use_case.dart';
import '../../application/use_cases/markdown/create_markdown_project_use_case.dart';
import '../../application/use_cases/markdown/get_markdown_projects_use_case.dart';
import '../../application/use_cases/markdown/delete_markdown_project_use_case.dart';
import '../../application/services/markdown_auto_save_service.dart';

/// Presentation state for the Markdown section.
///
/// Manages markdown files, projects, current file, filtering, and preview mode.
class MarkdownState extends ChangeNotifier {
  final CreateMarkdownFileUseCase _createFile;
  final GetMarkdownFilesUseCase _getFiles;
  final DeleteMarkdownFileUseCase _deleteFile;
  final CreateMarkdownProjectUseCase _createProject;
  final GetMarkdownProjectsUseCase _getProjects;
  final DeleteMarkdownProjectUseCase _deleteProject;
  final MarkdownAutoSaveService autoSaveService;

  List<MarkdownFile> _files = [];
  List<MarkdownProject> _projects = [];
  MarkdownFile? _currentFile;
  String? _selectedProjectId; // null = show all, '__root__' = root only
  String _searchQuery = '';
  bool _isLoading = false;
  bool _isPreviewMode = false;

  MarkdownState({
    required CreateMarkdownFileUseCase createFile,
    required GetMarkdownFilesUseCase getFiles,
    required UpdateMarkdownFileUseCase updateFile,
    required DeleteMarkdownFileUseCase deleteFile,
    required CreateMarkdownProjectUseCase createProject,
    required GetMarkdownProjectsUseCase getProjects,
    required DeleteMarkdownProjectUseCase deleteProject,
    required this.autoSaveService,
  })  : _createFile = createFile,
        _getFiles = getFiles,
        _deleteFile = deleteFile,
        _createProject = createProject,
        _getProjects = getProjects,
        _deleteProject = deleteProject {
    autoSaveService.onSaved = _onFileSaved;
  }

  // ── Getters ─────────────────────────────────────────────────────────────

  List<MarkdownFile> get files => _files;
  List<MarkdownProject> get projects => _projects;
  MarkdownFile? get currentFile => _currentFile;
  String? get selectedProjectId => _selectedProjectId;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  bool get isPreviewMode => _isPreviewMode;

  List<MarkdownFile> get filteredFiles {
    var result = _files;
    // Filter by project
    if (_selectedProjectId == '__root__') {
      result = result.where((f) => f.projectId == null).toList();
    } else if (_selectedProjectId != null) {
      result =
          result.where((f) => f.projectId == _selectedProjectId).toList();
    }
    // Filter by search
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((f) =>
              f.title.toLowerCase().contains(q) ||
              f.content.toLowerCase().contains(q))
          .toList();
    }
    return result;
  }

  // ── Initialization ──────────────────────────────────────────────────────

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    try {
      _files = await _getFiles.getAll();
      _projects = await _getProjects.getAll();
    } catch (e) {
      debugPrint('[MarkdownState] Initialize error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshFiles() async {
    _files = await _getFiles.getAll();
    notifyListeners();
  }

  // ── File operations ─────────────────────────────────────────────────────

  void selectFile(MarkdownFile file) {
    _currentFile = file;
    _isPreviewMode = false;
    notifyListeners();
  }

  void togglePreviewMode() {
    _isPreviewMode = !_isPreviewMode;
    notifyListeners();
  }

  void setPreviewMode(bool value) {
    _isPreviewMode = value;
    notifyListeners();
  }

  Future<MarkdownFile> createFile({String? projectId}) async {
    final file = await _createFile.execute(
      id: const Uuid().v4(),
      title: 'Untitled.md',
      projectId: projectId,
    );
    await refreshFiles();
    _currentFile = file;
    _isPreviewMode = false;
    notifyListeners();
    return file;
  }

  Future<void> deleteFile(String fileId) async {
    await _deleteFile.execute(fileId);
    await refreshFiles();
    if (_currentFile?.id == fileId) {
      _currentFile = _files.isNotEmpty ? _files.first : null;
    }
    notifyListeners();
  }

  void updateFileInList(MarkdownFile updated) {
    final idx = _files.indexWhere((f) => f.id == updated.id);
    if (idx >= 0) _files[idx] = updated;
    if (_currentFile?.id == updated.id) _currentFile = updated;
    notifyListeners();
  }

  // ── Project operations ──────────────────────────────────────────────────

  void filterByProject(String? projectId) {
    _selectedProjectId = projectId;
    notifyListeners();
  }

  void search(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<MarkdownProject> createProject({
    required String name,
    required int colorValue,
  }) async {
    final p = await _createProject.execute(
      id: const Uuid().v4(),
      name: name,
      colorValue: colorValue,
    );
    _projects = await _getProjects.getAll();
    notifyListeners();
    return p;
  }

  Future<void> deleteProject(String projectId) async {
    await _deleteProject.execute(projectId);
    _projects = await _getProjects.getAll();
    _files = await _getFiles.getAll();
    if (_selectedProjectId == projectId) _selectedProjectId = null;
    if (_currentFile?.projectId == projectId) {
      _currentFile = _files.isNotEmpty ? _files.first : null;
    }
    notifyListeners();
  }

  MarkdownProject? projectForId(String? id) {
    if (id == null) return null;
    return _projects.cast<MarkdownProject?>().firstWhere(
          (p) => p?.id == id,
          orElse: () => null,
        );
  }

  // ── Auto-save callback ─────────────────────────────────────────────────

  Future<void> _onFileSaved(String fileId) async {
    final updated = await _getFiles.getById(fileId);
    if (updated != null) updateFileInList(updated);
  }
}
