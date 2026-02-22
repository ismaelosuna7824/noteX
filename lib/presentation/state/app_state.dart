import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/entities/note.dart';
import '../../domain/value_objects/view_mode.dart';
import '../../application/use_cases/create_note_use_case.dart';
import '../../application/use_cases/get_notes_use_case.dart';
import '../../application/use_cases/delete_note_use_case.dart';
import '../../application/use_cases/update_note_use_case.dart';
import '../../application/services/auto_save_service.dart';
import '../../domain/repositories/auth_repository.dart';
import 'package:uuid/uuid.dart';

/// Central application state using ChangeNotifier.
///
/// Manages notes list, current note, view mode, and auth state.
class AppState extends ChangeNotifier {
  final CreateNoteUseCase _createNote;
  final GetNotesUseCase _getNotes;
  final DeleteNoteUseCase _deleteNote;
  final UpdateNoteUseCase _updateNote;
  final AutoSaveService autoSaveService;
  final AuthRepository _authRepository;

  List<Note> _notes = [];
  Note? _currentNote;
  ViewMode _viewMode = ViewMode.list;
  int _selectedPageIndex = 0;
  String _searchQuery = '';
  bool _isLoading = false;
  bool _showPinnedTab = false;
  String? _authErrorMessage;
  StreamSubscription<bool>? _authSub;

  AppState({
    required CreateNoteUseCase createNote,
    required GetNotesUseCase getNotes,
    required DeleteNoteUseCase deleteNote,
    required UpdateNoteUseCase updateNote,
    required this.autoSaveService,
    required AuthRepository authRepository,
  })  : _createNote = createNote,
        _getNotes = getNotes,
        _deleteNote = deleteNote,
        _updateNote = updateNote,
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

  // Getters
  List<Note> get notes => _notes;
  Note? get currentNote => _currentNote;
  ViewMode get viewMode => _viewMode;
  int get selectedPageIndex => _selectedPageIndex;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  bool get showPinnedTab => _showPinnedTab;
  bool get isAuthenticated => _authRepository.isAuthenticated;
  String? get userName => _authRepository.displayName;
  String? get userAvatar => _authRepository.avatarUrl;
  String? get authErrorMessage => _authErrorMessage;

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

  /// Filtered notes for display (applies search query if set).
  List<Note> get filteredNotes {
    if (_searchQuery.isEmpty) return _notes;
    final q = _searchQuery.toLowerCase();
    return _notes
        .where((n) =>
            n.title.toLowerCase().contains(q) ||
            n.content.toLowerCase().contains(q))
        .toList();
  }

  /// Initialize: load notes and ensure a daily note exists.
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      _notes = await _getNotes.getAll();

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
  }

  /// Called by AutoSaveService after a successful save.
  /// Re-fetches the saved note from DB to get the updated state.
  Future<void> _onNoteSaved(String noteId) async {
    final updated = await _getNotes.getById(noteId);
    if (updated != null) {
      updateNoteInList(updated);
    }
  }

  /// Refresh the notes list from the repository.
  Future<void> refreshNotes() async {
    _notes = await _getNotes.getAll();
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

  /// Create a new note.
  Future<Note> createNewNote() async {
    final note = await _createNote.execute(id: const Uuid().v4());
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

  /// Sign in with Google.
  Future<void> signIn() async {
    await _authRepository.signInWithGoogle();
    notifyListeners();
  }

  /// Sign in with Email and Password
  Future<bool> signInWithEmail(String email, String password) async {
    _isLoading = true;
    clearAuthError();
    notifyListeners();

    try {
      await _authRepository.signInWithEmail(email, password);
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
      return true;
    } catch (e) {
      _authErrorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
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
}
