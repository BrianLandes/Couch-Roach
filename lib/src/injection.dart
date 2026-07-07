import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

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

  // Backed by the storage_locations table; hydrated at startup via
  // `getIt<StorageManager>().load()` in main().
  @lazySingleton
  StorageManager storageManager(StorageRepository repo) =>
      ConfiguredStorageManager(repo);
}
