import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/entities/note.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../infrastructure/config/app_config.dart';
import '../../domain/entities/note_project.dart';
import '../../domain/value_objects/view_mode.dart';
import '../../application/use_cases/create_note_use_case.dart';
import '../../application/use_cases/get_notes_use_case.dart';
import '../../application/use_cases/delete_note_use_case.dart';
import '../../application/use_cases/update_note_use_case.dart';
import '../../application/use_cases/note/create_note_project_use_case.dart';
import '../../application/use_cases/note/get_note_projects_use_case.dart';
import '../../application/use_cases/note/delete_note_project_use_case.dart';
import '../../application/use_cases/note/rename_note_project_use_case.dart';
import '../../application/use_cases/note/get_deleted_notes_use_case.dart';
import '../../application/use_cases/note/restore_note_use_case.dart';
import '../../application/use_cases/note/permanent_delete_note_use_case.dart';
import '../../application/use_cases/check_for_update_use_case.dart';
import '../../application/use_cases/cleanup_empty_notes_use_case.dart';
import '../../application/use_cases/cleanup_expired_ephemeral_notes_use_case.dart';
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
  final RenameNoteProjectUseCase _renameNoteProject;
  final GetDeletedNotesUseCase _getDeletedNotes;
  final RestoreNoteUseCase _restoreNote;
  final PermanentDeleteNoteUseCase _permanentDeleteNote;
  final CheckForUpdateUseCase _checkForUpdate;
  final CleanupEmptyNotesUseCase _cleanupEmptyNotes;
  final CleanupExpiredEphemeralNotesUseCase _cleanupExpiredEphemeral;
  final UpdateService _updateService;
  final AutoSaveService autoSaveService;
  final AuthRepository _authRepository;
  SyncEngine? _syncEngine;

  List<Note> _notes = [];
  List<Note> _trashedNotes = [];
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

  // Editor tabs
  List<String> _openTabIds = [];

  // Compact / sticky note mode
  bool _isCompactMode = false;

  // Focus / zen mode
  bool _isZenMode = false;

  // Goodbye screen on close
  bool _isClosing = false;

  // Auto-update state
  UpdateInfo? _availableUpdate;
  bool _updateBannerDismissed = false;
  bool _isUpdating = false;
  double _updateProgress = 0.0;
  String? _updateError;

  AppState({
    required CreateNoteUseCase createNote,
    required GetNotesUseCase getNotes,
    required DeleteNoteUseCase deleteNote,
    required UpdateNoteUseCase updateNote,
    required CreateNoteProjectUseCase createNoteProject,
    required GetNoteProjectsUseCase getNoteProjects,
    required DeleteNoteProjectUseCase deleteNoteProject,
    required RenameNoteProjectUseCase renameNoteProject,
    required GetDeletedNotesUseCase getDeletedNotes,
    required RestoreNoteUseCase restoreNote,
    required PermanentDeleteNoteUseCase permanentDeleteNote,
    required CheckForUpdateUseCase checkForUpdate,
    required CleanupEmptyNotesUseCase cleanupEmptyNotes,
    required CleanupExpiredEphemeralNotesUseCase cleanupExpiredEphemeral,
    required UpdateService updateService,
    required this.autoSaveService,
    required AuthRepository authRepository,
  })  : _createNote = createNote,
        _getNotes = getNotes,
        _deleteNote = deleteNote,
        _updateNote = updateNote,
        _createNoteProject = createNoteProject,
        _getNoteProjects = getNoteProjects,
        _deleteNoteProject = deleteNoteProject,
        _renameNoteProject = renameNoteProject,
        _getDeletedNotes = getDeletedNotes,
        _restoreNote = restoreNote,
        _permanentDeleteNote = permanentDeleteNote,
        _checkForUpdate = checkForUpdate,
        _cleanupEmptyNotes = cleanupEmptyNotes,
        _cleanupExpiredEphemeral = cleanupExpiredEphemeral,
        _updateService = updateService,
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
  List<Note> get trashedNotes => _trashedNotes;
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
  bool get isCompactMode => _isCompactMode;
  bool get isZenMode => _isZenMode;
  bool get isClosing => _isClosing;

  /// Notes currently open as editor tabs.
  List<Note> get openTabs =>
      _openTabIds
          .map((id) => _notes.cast<Note?>().firstWhere(
                (n) => n?.id == id,
                orElse: () => null,
              ))
          .whereType<Note>()
          .toList();

  void startClosing() {
    _isClosing = true;
    notifyListeners();
  }
  bool get isUpdating => _isUpdating;
  double get updateProgress => _updateProgress;
  String? get updateError => _updateError;

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

      // Safety net: clean up orphaned empty notes and expired ephemeral notes
      final removed = await _cleanupEmptyNotes.execute();
      final expiredRemoved = await _cleanupExpiredEphemeral.execute();
      if (removed > 0 || expiredRemoved > 0) {
        _notes = await _getNotes.getAll();
      }

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

  /// Delete all notes with empty content and expired ephemeral notes.
  /// Called on app startup (initialize) and app close (onWindowClose).
  Future<void> cleanupEmptyNotes() async {
    await _cleanupEmptyNotes.execute();
    await _cleanupExpiredEphemeral.execute();
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
    if (!_openTabIds.contains(note.id)) {
      _openTabIds.add(note.id);
    }
    _currentNote = note;
    _selectedPageIndex = 2; // Navigate to editor
    notifyListeners();
  }

  /// Preview a note without navigating to the editor.
  void previewNote(Note note) {
    if (!_openTabIds.contains(note.id)) {
      _openTabIds.add(note.id);
    }
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

  /// Enter compact "sticky note" mode for a specific note.
  void enterCompactMode(Note note) {
    _currentNote = note;
    _isCompactMode = true;
    notifyListeners();
  }

  /// Exit compact mode and return to the full app.
  void exitCompactMode() {
    _isCompactMode = false;
    _selectedPageIndex = 1; // back to notes list
    notifyListeners();
  }

  /// Restore compact mode on startup using a saved note ID.
  /// Called from main.dart before the first frame.
  /// Returns true if the note was found and compact mode was restored,
  /// false if the note no longer exists (e.g. it was deleted as empty).
  bool restoreCompactMode(String noteId) {
    final note = _notes.cast<Note?>().firstWhere(
          (n) => n?.id == noteId,
          orElse: () => null,
        );
    if (note != null) {
      _currentNote = note;
      _isCompactMode = true;
      // notifyListeners will be called by the framework on first build.
      return true;
    }
    return false;
  }

  // ── Zen / Focus mode ─────────────────────────────────────────────────

  void enterZenMode() {
    if (_currentNote == null) return;
    _isZenMode = true;
    notifyListeners();
  }

  void exitZenMode() {
    _isZenMode = false;
    notifyListeners();
  }

  void toggleZenMode() {
    if (_isZenMode) {
      exitZenMode();
    } else {
      enterZenMode();
    }
  }

  // ── Editor tabs ──────────────────────────────────────────────────────

  /// Open a note as a tab and switch to it.
  void openTab(Note note) {
    if (!_openTabIds.contains(note.id)) {
      _openTabIds.add(note.id);
    }
    _currentNote = note;
    _selectedPageIndex = 2;
    notifyListeners();
  }

  /// Close a tab. Switches to adjacent tab or clears editor.
  void closeTab(String noteId) {
    final idx = _openTabIds.indexOf(noteId);
    if (idx < 0) return;
    _openTabIds.removeAt(idx);

    if (_currentNote?.id == noteId) {
      if (_openTabIds.isNotEmpty) {
        // Switch to the tab that's now at the same index (or the last one)
        final newIdx = idx.clamp(0, _openTabIds.length - 1);
        final newId = _openTabIds[newIdx];
        _currentNote = _notes.cast<Note?>().firstWhere(
              (n) => n?.id == newId,
              orElse: () => null,
            );
      } else {
        _currentNote = null;
        _selectedPageIndex = 1; // back to notes list
      }
    }
    notifyListeners();
  }

  /// Switch to an already-open tab.
  void switchTab(String noteId) {
    if (!_openTabIds.contains(noteId)) return;
    final note = _notes.cast<Note?>().firstWhere(
          (n) => n?.id == noteId,
          orElse: () => null,
        );
    if (note != null) {
      _currentNote = note;
      notifyListeners();
    }
  }

  /// Update the search query and filter notes in-memory.
  void search(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Create a new note, inheriting the current project filter.
  /// If [date] is provided, the note is created for that date instead of today.
  Future<Note> createNewNote({String? projectId, DateTime? date, bool isEphemeral = false}) async {
    // Use passed projectId, or inherit from filter (unless 'all' or '__root__')
    final effectiveProjectId = projectId ??
        (_selectedNoteProjectId != null &&
                _selectedNoteProjectId != '__root__'
            ? _selectedNoteProjectId
            : null);
    final note = await _createNote.execute(
      id: const Uuid().v4(),
      projectId: effectiveProjectId,
      date: date,
      isEphemeral: isEphemeral,
    );
    await refreshNotes();
    _currentNote = note;
    _selectedPageIndex = 2; // Navigate to editor
    notifyListeners();
    return note;
  }

  /// Create a quick (ephemeral) note — local-only, auto-deletes after 24h.
  Future<Note> createQuickNote({String? projectId}) async {
    return createNewNote(projectId: projectId, isEphemeral: true);
  }

  /// Toggle the ephemeral state of a note.
  Future<void> toggleEphemeral(String noteId) async {
    final existing = _notes.cast<Note?>().firstWhere(
          (n) => n?.id == noteId,
          orElse: () => null,
        );
    if (existing == null) return;
    final updated = await _updateNote.execute(
      noteId: noteId,
      isEphemeral: !existing.isEphemeral,
    );
    if (updated != null) {
      updateNoteInList(updated);
    }
  }

  /// Duplicate an existing note.
  Future<void> duplicateNote(Note note) async {
    final newNote = await _createNote.execute(
      id: const Uuid().v4(),
      title: '${note.title} (copy)',
      backgroundImage: note.backgroundImage,
      themeId: note.themeId,
      projectId: note.projectId,
    );
    await _updateNote.execute(
      noteId: newNote.id,
      content: note.content,
      color: note.color,
    );
    await refreshNotes();
    notifyListeners();
  }

  /// Share a note via a temporary public link. Returns the share URL.
  Future<String?> shareNote(Note note) async {
    if (!_authRepository.isAuthenticated) return null;
    final token = const Uuid().v4().replaceAll('-', '').substring(0, 16);

    final updated = await _updateNote.execute(
      noteId: note.id,
      shareToken: token,
      sharedAt: DateTime.now(),
    );
    if (updated == null) return null;
    updateNoteInList(updated);

    // Push immediately so the token is available on Supabase
    if (_syncEngine != null) {
      await _syncEngine!.syncIfAuthenticated();
    }

    // Construct the public Supabase REST URL
    final config = AppConfig.fromEnvironment();
    return '${config.supabaseUrl}/rest/v1/notes'
        '?share_token=eq.$token'
        '&select=title,content'
        '&apikey=${config.supabaseAnonKey}';
  }

  /// Import a note from a share link URL.
  /// Fetches the note data from Supabase and creates a local copy.
  /// Returns the created note title, or null on failure.
  Future<String?> importFromShareLink(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data is! List || data.isEmpty) return null;

      final noteData = data[0] as Map<String, dynamic>;
      final title = noteData['title'] as String? ?? 'Imported Note';
      final content = noteData['content'] as String? ?? '[]';

      final newNote = await _createNote.execute(
        id: const Uuid().v4(),
        title: title,
      );
      await _updateNote.execute(
        noteId: newNote.id,
        content: content,
      );
      await refreshNotes();
      notifyListeners();
      return title;
    } catch (_) {
      return null;
    }
  }

  /// Toggle the pin state of a note.
  /// Update the color of a note (pass null to clear).
  Future<void> updateNoteColor(Note note, String? color) async {
    final updated = await _updateNote.execute(
      noteId: note.id,
      color: color,
    );
    if (updated != null) {
      updateNoteInList(updated);
      if (_currentNote?.id == note.id) {
        _currentNote = updated;
      }
      notifyListeners();
    }
  }

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
    _openTabIds.remove(noteId);
    await refreshNotes();
    // If the deleted note was in compact mode, exit compact mode.
    if (_isCompactMode && _currentNote?.id == noteId) {
      _isCompactMode = false;
    }
    if (_currentNote?.id == noteId) {
      // Switch to another open tab, or fall back to first note
      if (_openTabIds.isNotEmpty) {
        _currentNote = _notes.cast<Note?>().firstWhere(
              (n) => n?.id == _openTabIds.last,
              orElse: () => _notes.isNotEmpty ? _notes.first : null,
            );
      } else {
        _currentNote = _notes.isNotEmpty ? _notes.first : null;
      }
    }
    notifyListeners();
  }

  // ── Trash operations ─────────────────────────────────────────────────

  /// Load all soft-deleted notes into the trash list.
  Future<void> loadTrash() async {
    _trashedNotes = await _getDeletedNotes.execute();
    notifyListeners();
  }

  /// Restore a note from the trash back to the notes list.
  Future<void> restoreNote(String noteId) async {
    await _restoreNote.execute(noteId);
    _trashedNotes = await _getDeletedNotes.execute();
    _notes = await _getNotes.getAll();
    notifyListeners();
  }

  /// Permanently delete a note (hard delete from DB).
  Future<void> permanentDeleteNote(String noteId) async {
    await _permanentDeleteNote.execute(noteId);
    _trashedNotes = await _getDeletedNotes.execute();
    notifyListeners();
  }

  /// Empty the entire trash (permanently delete all trashed notes).
  Future<void> emptyTrash() async {
    final ids = _trashedNotes.map((n) => n.id).toList();
    for (final id in ids) {
      await _permanentDeleteNote.execute(id);
    }
    _trashedNotes = [];
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

  /// Rename an existing note project.
  Future<void> renameNoteProject(String projectId, String newName) async {
    await _renameNoteProject.execute(projectId: projectId, newName: newName);
    _noteProjects = await _getNoteProjects.getAll();
    notifyListeners();
  }

  /// Change the category (NoteProject) of an existing note.
  Future<void> updateNoteProject(String noteId, String? projectId) async {
    final updated = await _updateNote.execute(
      noteId: noteId,
      projectId: projectId,
    );
    if (updated != null) {
      updateNoteInList(updated);
    }
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
        // First login or user switch — data was synced, reload everything
        await refreshNotes();
      } else {
        // Same user returning — sync pending changes
        await _syncEngine!.sync();
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

  /// Download and apply the update in-place (silent install on Windows).
  ///
  /// Auto-saves any pending work before launching the installer.
  Future<void> applyUpdate() async {
    final update = _availableUpdate;
    if (update == null || _isUpdating) return;

    _isUpdating = true;
    _updateProgress = 0.0;
    _updateError = null;
    notifyListeners();

    try {
      await _updateService.applyUpdate(
        update,
        onProgress: (progress) {
          _updateProgress = progress;
          notifyListeners();
        },
      );
      // On Windows applyUpdate calls exit(0), so we won't reach here.
      // On macOS/Linux it opens the browser and returns normally.
      _isUpdating = false;
      notifyListeners();
    } catch (e) {
      _isUpdating = false;
      _updateError = 'Update failed: $e';
      notifyListeners();
    }
  }

  /// Hide the update banner for this session.
  void dismissUpdateBanner() {
    _updateBannerDismissed = true;
    notifyListeners();
  }
}
