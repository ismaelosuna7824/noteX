import 'package:get_it/get_it.dart';

import 'domain/repositories/note_repository.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/services/sync_service.dart';
import 'domain/services/title_generation_service.dart';

import 'infrastructure/local/database.dart';
import 'infrastructure/local/drift_note_repository.dart';
import 'infrastructure/auth/firebase_auth_adapter.dart';
import 'infrastructure/firebase/firebase_sync_adapter.dart';
import 'infrastructure/api/title_api_adapter.dart';
import 'infrastructure/config/app_config.dart';

import 'application/use_cases/create_note_use_case.dart';
import 'application/use_cases/update_note_use_case.dart';
import 'application/use_cases/get_notes_use_case.dart';
import 'application/use_cases/delete_note_use_case.dart';
import 'application/use_cases/generate_title_use_case.dart';
import 'application/services/auto_save_service.dart';
import 'application/services/sync_orchestrator.dart';

import 'presentation/state/app_state.dart';
import 'presentation/state/theme_state.dart';

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
  getIt.registerSingleton<AuthRepository>(
    FirebaseAuthAdapter(),
  );
  getIt.registerSingleton<SyncService>(
    FirebaseSyncAdapter(),
  );
  getIt.registerSingleton<TitleGenerationService>(
    TitleApiAdapter(),
  );

  // Application - Use Cases
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

  // Application - Services
  getIt.registerSingleton<SyncOrchestrator>(
    SyncOrchestrator(
      getIt<NoteRepository>(),
      getIt<AuthRepository>(),
      getIt<SyncService>(),
    ),
  );
  getIt.registerSingleton<AutoSaveService>(
    AutoSaveService(
      getIt<UpdateNoteUseCase>(),
      getIt<SyncOrchestrator>(),
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
}
