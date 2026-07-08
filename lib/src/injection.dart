import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import 'core/logging/error_log_service.dart';
import 'core/storage/storage_manager.dart';
import 'data/db/database.dart';
import 'data/repositories/storage_repository.dart';

import 'injection.config.dart';

/// Service locator. All services and singletons register here via `injectable`
/// annotations (`@LazySingleton` / `@Singleton`) and are resolved with
/// `getIt<T>()`. See CLAUDE.md → Services.
final getIt = GetIt.instance;

@InjectableInit()
void configureDependencies() => getIt.init();

/// Provides third-party / manually-constructed singletons to the container so
/// annotated services can take them as constructor parameters.
@module
abstract class RegisterModule {
  @lazySingleton
  AppDatabase get database => AppDatabase();

  /// Shared HTTP client for the API clients (TMDB, later OpenSubtitles).
  @lazySingleton
  http.Client get httpClient => http.Client();

  // Backed by the storage_locations table; hydrated at startup via
  // `getIt<StorageManager>().load()` in main().
  @lazySingleton
  StorageManager storageManager(StorageRepository repo, ErrorLogService log) =>
      ConfiguredStorageManager(repo, log: log);
}
