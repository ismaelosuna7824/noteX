import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'domain/repositories/note_repository.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/repositories/project_repository.dart';
import 'domain/repositories/time_entry_repository.dart';
import 'domain/services/sync_service.dart';
import 'domain/services/connectivity_service.dart';
import 'domain/services/title_generation_service.dart';

import 'infrastructure/local/database.dart';
import 'infrastructure/local/drift_note_repository.dart';
import 'infrastructure/local/drift_project_repository.dart';
import 'infrastructure/local/drift_time_entry_repository.dart';
import 'infrastructure/auth/supabase_auth_adapter.dart';
import 'infrastructure/supabase/supabase_sync_adapter.dart';
import 'infrastructure/network/connectivity_adapter.dart';
import 'infrastructure/api/title_api_adapter.dart';
import 'infrastructure/config/app_config.dart';

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
import 'application/services/auto_save_service.dart';
import 'application/services/sync_engine.dart';

import 'presentation/state/app_state.dart';
import 'presentation/state/theme_state.dart';
import 'presentation/state/timer_state.dart';

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
  final appConfig = getIt<AppConfig>();
  getIt.registerSingleton<AuthRepository>(
    SupabaseAuthAdapter(
      supabaseClient,
      googleClientId: appConfig.googleClientId,
    ),
  );

  // Infrastructure - Connectivity
  getIt.registerSingleton<ConnectivityService>(
    ConnectivityAdapter(),
  );

  getIt.registerSingleton<TitleGenerationService>(
    TitleApiAdapter(),
  );

  // Infrastructure - Timer Repositories
  getIt.registerSingleton<ProjectRepository>(
    DriftProjectRepository(database),
  );
  getIt.registerSingleton<TimeEntryRepository>(
    DriftTimeEntryRepository(database),
  );

  // Infrastructure - Sync Service (Supabase adapter)
  getIt.registerSingleton<SyncService>(
    SupabaseSyncAdapter(
      supabase: supabaseClient,
      db: database,
      noteRepo: getIt<NoteRepository>(),
      projectRepo: getIt<ProjectRepository>(),
      timeEntryRepo: getIt<TimeEntryRepository>(),
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

  // Presentation - State
  getIt.registerSingleton<ThemeState>(ThemeState());
  getIt.registerSingleton<AppState>(
    AppState(
      createNote: getIt<CreateNoteUseCase>(),
      getNotes: getIt<GetNotesUseCase>(),
      deleteNote: getIt<DeleteNoteUseCase>(),
      updateNote: getIt<UpdateNoteUseCase>(),
      autoSaveService: getIt<AutoSaveService>(),
      authRepository: getIt<AuthRepository>(),
    ),
  );
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
}
