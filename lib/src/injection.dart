import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'core/storage/storage_manager.dart';
import 'data/db/database.dart';

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

  // Roots are loaded from the `storage_locations` table at runtime; start empty.
  // TODO(storage): hydrate roots from the DB during startup.
  @lazySingleton
  StorageManager storageManager() => ConfiguredStorageManager(const []);
}
