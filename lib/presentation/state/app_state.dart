import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/entities/note.dart';
import '../../domain/entities/note_project.dart';
import '../../domain/value_objects/view_mode.dart';
import '../../application/use_cases/create_note_use_case.dart';
import '../../application/use_cases/get_notes_use_case.dart';
import '../../application/use_cases/delete_note_use_case.dart';
import '../../application/use_cases/update_note_use_case.dart';
import '../../application/use_cases/note/create_note_project_use_case.dart';
import '../../application/use_cases/note/get_note_projects_use_case.dart';
import '../../application/use_cases/note/delete_note_project_use_case.dart';
import '../../application/use_cases/check_for_update_use_case.dart';
import '../../application/services/auto_save_service.dart';
import '../../application/services/sync_engine.dart';
import '../../domain/repositories/auth_repository.dart'
    show AuthRepository, GoogleSignInCancelledException;
import '../../domain/services/update_service.dart';
import 'package:uuid/uuid.dart';

/// Central application state using ChangeNotifier.
///
/// Manages notes list, current note, view mode, and auth state.
class AppState extends ChangeNotifier {
  final CreateNoteUseCase _createNote;
  final GetNotesUseCase _getNotes;
  final DeleteNoteUseCase _deleteNote;
  final UpdateNoteUseCase _updateNote;
  final CreateNoteProjectUseCase _createNoteProject;
  final GetNoteProjectsUseCase _getNoteProjects;
  final DeleteNoteProjectUseCase _deleteNoteProject;
  final CheckForUpdateUseCase _checkForUpdate;
  final AutoSaveService autoSaveService;
  final AuthRepository _authRepository;
  SyncEngine? _syncEngine;

  List<Note> _notes = [];
  List<NoteProject> _noteProjects = [];
  Note? _currentNote;
  ViewMode _viewMode = ViewMode.list;
  int _selectedPageIndex = 0;
  String _searchQuery = '';
  String? _selectedNoteProjectId; // null = all, '__root__' = uncategorized
  bool _isLoading = false;
  bool _showPinnedTab = false;
  String? _authErrorMessage;
  StreamSubscription<bool>? _authSub;

  // Auto-update state
  UpdateInfo? _availableUpdate;
  bool _updateBannerDismissed = false;

  AppState({
    required CreateNoteUseCase createNote,
    required GetNotesUseCase getNotes,
    required DeleteNoteUseCase deleteNote,
    required UpdateNoteUseCase updateNote,
    required CreateNoteProjectUseCase createNoteProject,
    required GetNoteProjectsUseCase getNoteProjects,
    required DeleteNoteProjectUseCase deleteNoteProject,
    required CheckForUpdateUseCase checkForUpdate,
    required this.autoSaveService,
    required AuthRepository authRepository,
  })  : _createNote = createNote,
        _getNotes = getNotes,
        _deleteNote = deleteNote,
        _updateNote = updateNote,
        _createNoteProject = createNoteProject,
        _getNoteProjects = getNoteProjects,
        _deleteNoteProject = deleteNoteProject,
        _checkForUpdate = checkForUpdate,
        _authRepository = authRepository {
    // Wire up auto-save callback to refresh the list after saves
    autoSaveService.onSaved = _onNoteSaved;

    // React to Supabase auth state changes (sign-in/sign-out come in async)
    _authSub = _authRepository.authStateChanges.listen((_) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// Late-wired to avoid circular dependency in DI.
  set syncEngine(SyncEngine engine) => _syncEngine = engine;

  // Getters
  List<Note> get notes => _notes;
  List<NoteProject> get noteProjects => _noteProjects;
  Note? get currentNote => _currentNote;
  ViewMode get viewMode => _viewMode;
  int get selectedPageIndex => _selectedPageIndex;
  String get searchQuery => _searchQuery;
  String? get selectedNoteProjectId => _selectedNoteProjectId;
  bool get isLoading => _isLoading;
  bool get showPinnedTab => _showPinnedTab;
  bool get isAuthenticated => _authRepository.isAuthenticated;
  String? get userName => _authRepository.displayName;
  String? get userAvatar => _authRepository.avatarUrl;
  String? get authErrorMessage => _authErrorMessage;
  UpdateInfo? get availableUpdate => _availableUpdate;
  bool get hasUpdate => _availableUpdate != null;
  bool get showUpdateBanner => _availableUpdate != null && !_updateBannerDismissed;

  /// Clear any existing authentication errors
  void clearAuthError() {
    if (_authErrorMessage != null) {
      _authErrorMessage = null;
      notifyListeners();
    }
  }

  // ... (leaving getters below unchanged)

  /// All pinned notes.
  List<Note> get pinnedNotes => _notes.where((n) => n.isPinned).toList();

  /// Filtered notes for display (applies project filter + search query).
  List<Note> get filteredNotes {
    var result = _notes;
    // Filter by project
    if (_selectedNoteProjectId == '__root__') {
      result = result.where((n) => n.projectId == null).toList();
    } else if (_selectedNoteProjectId != null) {
      result = result
          .where((n) => n.projectId == _selectedNoteProjectId)
          .toList();
    }
    // Filter by search
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((n) =>
              n.title.toLowerCase().contains(q) ||
              n.content.toLowerCase().contains(q))
          .toList();
    }
    return result;
  }

  /// Initialize: load notes and ensure a daily note exists.
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      _notes = await _getNotes.getAll();
      _noteProjects = await _getNoteProjects.getAll();

      // Auto-create daily note if none exists for today
      final today = DateTime.now();
      final hasTodayNote = _notes.any((n) => n.isForDate(today));
      if (!hasTodayNote) {
        final dailyNote = await _createNote.execute(
          id: const Uuid().v4(),
          ensureDaily: true,
        );
        _notes.insert(0, dailyNote);
      }

      // Set today's note as current
      _currentNote = _notes.firstWhere(
        (n) => n.isForDate(today),
        orElse: () => _notes.first,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[AppState] Initialize error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    // Non-blocking update check — runs in background after startup
    checkForUpdate();
  }

  /// Called by AutoSaveService after a successful save.
  /// Re-fetches the saved note from DB to get the updated state.
  Future<void> _onNoteSaved(String noteId) async {
    final updated = await _getNotes.getById(noteId);
    if (updated != null) {
      updateNoteInList(updated);
    }
  }

  /// Refresh the notes list and projects from the repository.
  Future<void> refreshNotes() async {
    _notes = await _getNotes.getAll();
    _noteProjects = await _getNoteProjects.getAll();
    notifyListeners();
  }

  /// Set the current note being viewed/edited.
  void selectNote(Note note) {
    _currentNote = note;
    _selectedPageIndex = 2; // Navigate to editor
    notifyListeners();
  }

  /// Preview a note without navigating to the editor.
  void previewNote(Note note) {
    _currentNote = note;
    notifyListeners();
  }

  /// Switch between list and calendar view modes.
  void setViewMode(ViewMode mode) {
    _viewMode = mode;
    notifyListeners();
  }

  /// Navigate to a specific page via the sidebar.
  void navigateToPage(int index) {
    _selectedPageIndex = index;
    notifyListeners();
  }

  /// Update the search query and filter notes in-memory.
  void search(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Create a new note, inheriting the current project filter.
  Future<Note> createNewNote({String? projectId}) async {
    // Use passed projectId, or inherit from filter (unless 'all' or '__root__')
    final effectiveProjectId = projectId ??
        (_selectedNoteProjectId != null &&
                _selectedNoteProjectId != '__root__'
            ? _selectedNoteProjectId
            : null);
    final note = await _createNote.execute(
      id: const Uuid().v4(),
      projectId: effectiveProjectId,
    );
    await refreshNotes();
    _currentNote = note;
    _selectedPageIndex = 2; // Navigate to editor
    notifyListeners();
    return note;
  }

  /// Toggle the pin state of a note.
  Future<void> togglePin(Note note) async {
    final updated = await _updateNote.execute(
      noteId: note.id,
      isPinned: !note.isPinned,
    );
    if (updated != null) {
      updateNoteInList(updated);
    }
  }

  /// Navigate to the Notes List page and activate the Pinned tab.
  void navigateToPinnedNotes() {
    _showPinnedTab = true;
    _selectedPageIndex = 1;
    notifyListeners();
  }

  /// Switch the notes list tab (all vs pinned).
  void setShowPinnedTab(bool value) {
    _showPinnedTab = value;
    notifyListeners();
  }

  /// Delete a note.
  Future<void> deleteNote(String noteId) async {
    await _deleteNote.execute(noteId);
    await refreshNotes();
    if (_currentNote?.id == noteId) {
      _currentNote = _notes.isNotEmpty ? _notes.first : null;
    }
    notifyListeners();
  }

  // ── Note Project operations ──────────────────────────────────────────

  /// Filter notes by project.
  void filterByNoteProject(String? projectId) {
    _selectedNoteProjectId = projectId;
    notifyListeners();
  }

  /// Create a new note project.
  Future<NoteProject> createNoteProject({
    required String name,
    required int colorValue,
  }) async {
    final p = await _createNoteProject.execute(
      id: const Uuid().v4(),
      name: name,
      colorValue: colorValue,
    );
    _noteProjects = await _getNoteProjects.getAll();
    notifyListeners();
    return p;
  }

  /// Delete a note project and its notes.
  Future<void> deleteNoteProject(String projectId) async {
    await _deleteNoteProject.execute(projectId);
    _noteProjects = await _getNoteProjects.getAll();
    _notes = await _getNotes.getAll();
    if (_selectedNoteProjectId == projectId) _selectedNoteProjectId = null;
    if (_currentNote?.projectId == projectId) {
      _currentNote = _notes.isNotEmpty ? _notes.first : null;
    }
    notifyListeners();
  }

  /// Find a note project by id.
  NoteProject? noteProjectForId(String? id) {
    if (id == null) return null;
    return _noteProjects.cast<NoteProject?>().firstWhere(
          (p) => p?.id == id,
          orElse: () => null,
        );
  }

  /// Sign in with Google.
  Future<bool> signIn() async {
    _isLoading = true;
    clearAuthError();
    notifyListeners();

    try {
      await _authRepository.signInWithGoogle();
      await _onSignInSuccess();
      return true;
    } on GoogleSignInCancelledException {
      // User cancelled — silently reset, no error message shown.
      return false;
    } catch (e) {
      _authErrorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Cancel an in-progress Google Sign-In (user closed the browser window).
  Future<void> cancelGoogleSignIn() async {
    await _authRepository.cancelGoogleSignIn();
    // Loading state will be reset by the finally block in [signIn()],
    // but we reset here too in case the call order differs.
    _isLoading = false;
    notifyListeners();
  }

  /// Sign in with Email and Password
  Future<bool> signInWithEmail(String email, String password) async {
    _isLoading = true;
    clearAuthError();
    notifyListeners();

    try {
      await _authRepository.signInWithEmail(email, password);
      await _onSignInSuccess();
      return true;
    } catch (e) {
      _authErrorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sign up with Email and Password
  Future<bool> signUpWithEmail(String email, String password) async {
    _isLoading = true;
    clearAuthError();
    notifyListeners();

    try {
      await _authRepository.signUpWithEmail(email, password);
      await _onSignInSuccess();
      return true;
    } catch (e) {
      _authErrorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Called after any successful sign-in (Google, email, sign-up).
  /// Detects account switch and clears local data if needed, then refreshes.
  Future<void> _onSignInSuccess() async {
    if (_syncEngine != null) {
      final switched = await _syncEngine!.handleUserSwitch();
      if (switched) {
        // Data was cleared and re-pulled — reload everything
        await refreshNotes();
      }
    }
  }

  /// Sign out.
  Future<void> signOut() async {
    await _authRepository.signOut();
    notifyListeners();
  }

  /// Update the current note in the local list (after auto-save).
  void updateNoteInList(Note updatedNote) {
    final index = _notes.indexWhere((n) => n.id == updatedNote.id);
    if (index >= 0) {
      _notes[index] = updatedNote;
    }
    if (_currentNote?.id == updatedNote.id) {
      _currentNote = updatedNote;
    }
    notifyListeners();
  }

  // ── Auto-update ──────────────────────────────────────────────────────

  /// Check GitHub Releases for a newer version. Fails silently.
  Future<void> checkForUpdate() async {
    try {
      _availableUpdate = await _checkForUpdate.execute();
      if (_availableUpdate != null) {
        _updateBannerDismissed = false;
        notifyListeners();
      }
    } catch (_) {
      // Network errors etc. — don't bother the user.
    }
  }

  /// Hide the update banner for this session.
  void dismissUpdateBanner() {
    _updateBannerDismissed = true;
    notifyListeners();
  }
}
