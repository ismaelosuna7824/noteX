import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'domain/repositories/note_repository.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/repositories/project_repository.dart';
import 'domain/repositories/time_entry_repository.dart';
import 'domain/repositories/markdown_file_repository.dart';
import 'domain/repositories/markdown_project_repository.dart';
import 'domain/repositories/note_project_repository.dart';
import 'domain/services/sync_service.dart';
import 'domain/services/connectivity_service.dart';
import 'domain/services/title_generation_service.dart';
import 'domain/services/update_service.dart';

import 'infrastructure/local/database.dart';
import 'infrastructure/local/drift_note_repository.dart';
import 'infrastructure/local/drift_project_repository.dart';
import 'infrastructure/local/drift_time_entry_repository.dart';
import 'infrastructure/local/drift_markdown_file_repository.dart';
import 'infrastructure/local/drift_markdown_project_repository.dart';
import 'infrastructure/local/drift_note_project_repository.dart';
import 'infrastructure/auth/supabase_auth_adapter.dart';
import 'infrastructure/supabase/supabase_sync_adapter.dart';
import 'infrastructure/network/connectivity_adapter.dart';
import 'infrastructure/api/title_api_adapter.dart';
import 'infrastructure/config/app_config.dart';
import 'infrastructure/update/github_update_adapter.dart';

import 'application/use_cases/create_note_use_case.dart';
import 'application/use_cases/update_note_use_case.dart';
import 'application/use_cases/get_notes_use_case.dart';
import 'application/use_cases/delete_note_use_case.dart';
import 'application/use_cases/generate_title_use_case.dart';
import 'application/use_cases/timer/create_project_use_case.dart';
import 'application/use_cases/timer/get_projects_use_case.dart';
import 'application/use_cases/timer/delete_project_use_case.dart';
import 'application/use_cases/timer/start_timer_use_case.dart';
import 'application/use_cases/timer/stop_timer_use_case.dart';
import 'application/use_cases/timer/get_time_entries_use_case.dart';
import 'application/use_cases/timer/delete_time_entry_use_case.dart';
import 'application/use_cases/timer/update_time_entry_use_case.dart';
import 'application/use_cases/markdown/create_markdown_file_use_case.dart';
import 'application/use_cases/markdown/update_markdown_file_use_case.dart';
import 'application/use_cases/markdown/get_markdown_files_use_case.dart';
import 'application/use_cases/markdown/delete_markdown_file_use_case.dart';
import 'application/use_cases/markdown/create_markdown_project_use_case.dart';
import 'application/use_cases/markdown/get_markdown_projects_use_case.dart';
import 'application/use_cases/markdown/delete_markdown_project_use_case.dart';
import 'application/use_cases/note/create_note_project_use_case.dart';
import 'application/use_cases/note/get_note_projects_use_case.dart';
import 'application/use_cases/note/delete_note_project_use_case.dart';
import 'application/use_cases/check_for_update_use_case.dart';
import 'application/services/auto_save_service.dart';
import 'application/services/markdown_auto_save_service.dart';
import 'application/services/sync_engine.dart';

import 'presentation/state/app_state.dart';
import 'presentation/state/theme_state.dart';
import 'presentation/state/timer_state.dart';
import 'presentation/state/markdown_state.dart';

final getIt = GetIt.instance;

/// Setup all dependency injection bindings.
///
/// Order: Config → Infrastructure → Use Cases → Services → State
Future<void> setupDependencies() async {
  // Config
  getIt.registerSingleton<AppConfig>(AppConfig.fromEnvironment());

  // Infrastructure - Database
  final database = AppDatabase();
  getIt.registerSingleton<AppDatabase>(database);

  // Infrastructure - Repositories (Adapters implementing domain ports)
  getIt.registerSingleton<NoteRepository>(
    DriftNoteRepository(database),
  );

  // Infrastructure - Supabase Auth
  final supabaseClient = Supabase.instance.client;
  getIt.registerSingleton<AuthRepository>(
    SupabaseAuthAdapter(supabaseClient),
  );

  // Infrastructure - Connectivity
  getIt.registerSingleton<ConnectivityService>(
    ConnectivityAdapter(),
  );

  getIt.registerSingleton<TitleGenerationService>(
    TitleApiAdapter(),
  );

  // Infrastructure - Update Service (GitHub Releases)
  getIt.registerSingleton<UpdateService>(
    GitHubUpdateAdapter(),
  );

  // Infrastructure - Timer Repositories
  getIt.registerSingleton<ProjectRepository>(
    DriftProjectRepository(database),
  );
  getIt.registerSingleton<TimeEntryRepository>(
    DriftTimeEntryRepository(database),
  );

  // Infrastructure - Markdown Repositories
  getIt.registerSingleton<MarkdownFileRepository>(
    DriftMarkdownFileRepository(database),
  );
  getIt.registerSingleton<MarkdownProjectRepository>(
    DriftMarkdownProjectRepository(database),
  );

  // Infrastructure - Note Project Repository
  getIt.registerSingleton<NoteProjectRepository>(
    DriftNoteProjectRepository(database),
  );

  // Infrastructure - Sync Service (Supabase adapter)
  getIt.registerSingleton<SyncService>(
    SupabaseSyncAdapter(
      supabase: supabaseClient,
      db: database,
      noteRepo: getIt<NoteRepository>(),
      projectRepo: getIt<ProjectRepository>(),
      timeEntryRepo: getIt<TimeEntryRepository>(),
      mdFileRepo: getIt<MarkdownFileRepository>(),
      mdProjectRepo: getIt<MarkdownProjectRepository>(),
      noteProjectRepo: getIt<NoteProjectRepository>(),
    ),
  );

  // Application - Note Use Cases
  getIt.registerFactory<CreateNoteUseCase>(
    () => CreateNoteUseCase(getIt<NoteRepository>()),
  );
  getIt.registerFactory<UpdateNoteUseCase>(
    () => UpdateNoteUseCase(getIt<NoteRepository>()),
  );
  getIt.registerFactory<GetNotesUseCase>(
    () => GetNotesUseCase(getIt<NoteRepository>()),
  );
  getIt.registerFactory<DeleteNoteUseCase>(
    () => DeleteNoteUseCase(getIt<NoteRepository>()),
  );
  getIt.registerFactory<GenerateTitleUseCase>(
    () => GenerateTitleUseCase(
      getIt<NoteRepository>(),
      getIt<TitleGenerationService>(),
      getIt<UpdateNoteUseCase>(),
    ),
  );

  // Application - Timer Use Cases
  getIt.registerFactory<CreateProjectUseCase>(
    () => CreateProjectUseCase(getIt<ProjectRepository>()),
  );
  getIt.registerFactory<GetProjectsUseCase>(
    () => GetProjectsUseCase(getIt<ProjectRepository>()),
  );
  getIt.registerFactory<DeleteProjectUseCase>(
    () => DeleteProjectUseCase(getIt<ProjectRepository>()),
  );
  getIt.registerFactory<StartTimerUseCase>(
    () => StartTimerUseCase(getIt<TimeEntryRepository>()),
  );
  getIt.registerFactory<StopTimerUseCase>(
    () => StopTimerUseCase(getIt<TimeEntryRepository>()),
  );
  getIt.registerFactory<GetTimeEntriesUseCase>(
    () => GetTimeEntriesUseCase(getIt<TimeEntryRepository>()),
  );
  getIt.registerFactory<DeleteTimeEntryUseCase>(
    () => DeleteTimeEntryUseCase(getIt<TimeEntryRepository>()),
  );
  getIt.registerFactory<UpdateTimeEntryUseCase>(
    () => UpdateTimeEntryUseCase(getIt<TimeEntryRepository>()),
  );

  // Application - Markdown Use Cases
  getIt.registerFactory<CreateMarkdownFileUseCase>(
    () => CreateMarkdownFileUseCase(getIt<MarkdownFileRepository>()),
  );
  getIt.registerFactory<UpdateMarkdownFileUseCase>(
    () => UpdateMarkdownFileUseCase(getIt<MarkdownFileRepository>()),
  );
  getIt.registerFactory<GetMarkdownFilesUseCase>(
    () => GetMarkdownFilesUseCase(getIt<MarkdownFileRepository>()),
  );
  getIt.registerFactory<DeleteMarkdownFileUseCase>(
    () => DeleteMarkdownFileUseCase(
      getIt<MarkdownFileRepository>(),
      getIt<SyncEngine>(),
    ),
  );
  getIt.registerFactory<CreateMarkdownProjectUseCase>(
    () => CreateMarkdownProjectUseCase(getIt<MarkdownProjectRepository>()),
  );
  getIt.registerFactory<GetMarkdownProjectsUseCase>(
    () => GetMarkdownProjectsUseCase(getIt<MarkdownProjectRepository>()),
  );
  getIt.registerFactory<DeleteMarkdownProjectUseCase>(
    () => DeleteMarkdownProjectUseCase(
      getIt<MarkdownProjectRepository>(),
      getIt<MarkdownFileRepository>(),
      getIt<SyncEngine>(),
    ),
  );

  // Application - Note Project Use Cases
  getIt.registerFactory<CreateNoteProjectUseCase>(
    () => CreateNoteProjectUseCase(getIt<NoteProjectRepository>()),
  );
  getIt.registerFactory<GetNoteProjectsUseCase>(
    () => GetNoteProjectsUseCase(getIt<NoteProjectRepository>()),
  );
  getIt.registerFactory<DeleteNoteProjectUseCase>(
    () => DeleteNoteProjectUseCase(
      getIt<NoteProjectRepository>(),
      getIt<NoteRepository>(),
      getIt<SyncEngine>(),
    ),
  );

  // Application - Update Use Case
  getIt.registerFactory<CheckForUpdateUseCase>(
    () => CheckForUpdateUseCase(getIt<UpdateService>()),
  );

  // Application - Services
  getIt.registerSingleton<SyncEngine>(
    SyncEngine(
      auth: getIt<AuthRepository>(),
      syncService: getIt<SyncService>(),
      connectivity: getIt<ConnectivityService>(),
    ),
  );
  getIt.registerSingleton<AutoSaveService>(
    AutoSaveService(
      getIt<UpdateNoteUseCase>(),
      getIt<SyncEngine>(),
    ),
  );
  getIt.registerSingleton<MarkdownAutoSaveService>(
    MarkdownAutoSaveService(
      getIt<UpdateMarkdownFileUseCase>(),
      getIt<SyncEngine>(),
    ),
  );

  // Presentation - State
  getIt.registerSingleton<ThemeState>(ThemeState());
  final appState = AppState(
    createNote: getIt<CreateNoteUseCase>(),
    getNotes: getIt<GetNotesUseCase>(),
    deleteNote: getIt<DeleteNoteUseCase>(),
    updateNote: getIt<UpdateNoteUseCase>(),
    createNoteProject: getIt<CreateNoteProjectUseCase>(),
    getNoteProjects: getIt<GetNoteProjectsUseCase>(),
    deleteNoteProject: getIt<DeleteNoteProjectUseCase>(),
    autoSaveService: getIt<AutoSaveService>(),
    authRepository: getIt<AuthRepository>(),
    checkForUpdate: getIt<CheckForUpdateUseCase>(),
    updateService: getIt<UpdateService>(),
  );
  getIt.registerSingleton<AppState>(appState);
  // Wire sync completion callback so the UI refreshes sync icons after each sync
  getIt<SyncEngine>().onSyncComplete = appState.refreshNotes;
  // Wire sync engine to AppState for user switch detection on sign-in
  appState.syncEngine = getIt<SyncEngine>();
  // TimerState owns a dart:async Timer → must be a singleton
  getIt.registerSingleton<TimerState>(
    TimerState(
      createProject: getIt<CreateProjectUseCase>(),
      getProjects: getIt<GetProjectsUseCase>(),
      deleteProject: getIt<DeleteProjectUseCase>(),
      startTimer: getIt<StartTimerUseCase>(),
      stopTimer: getIt<StopTimerUseCase>(),
      getEntries: getIt<GetTimeEntriesUseCase>(),
      deleteEntry: getIt<DeleteTimeEntryUseCase>(),
      updateEntry: getIt<UpdateTimeEntryUseCase>(),
    ),
  );
  // MarkdownState
  getIt.registerSingleton<MarkdownState>(
    MarkdownState(
      createFile: getIt<CreateMarkdownFileUseCase>(),
      getFiles: getIt<GetMarkdownFilesUseCase>(),
      updateFile: getIt<UpdateMarkdownFileUseCase>(),
      deleteFile: getIt<DeleteMarkdownFileUseCase>(),
      createProject: getIt<CreateMarkdownProjectUseCase>(),
      getProjects: getIt<GetMarkdownProjectsUseCase>(),
      deleteProject: getIt<DeleteMarkdownProjectUseCase>(),
      autoSaveService: getIt<MarkdownAutoSaveService>(),
    ),
  );
}
