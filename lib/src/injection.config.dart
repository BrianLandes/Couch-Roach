// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:couch_roach/src/core/logging/error_log_service.dart' as _i657;
import 'package:couch_roach/src/core/storage/storage_manager.dart' as _i883;
import 'package:couch_roach/src/data/db/database.dart' as _i865;
import 'package:couch_roach/src/data/repositories/library_repository.dart'
    as _i877;
import 'package:couch_roach/src/data/repositories/storage_repository.dart'
    as _i366;
import 'package:couch_roach/src/data/repositories/watch_history_repository.dart'
    as _i382;
import 'package:couch_roach/src/features/library/library_service.dart' as _i38;
import 'package:couch_roach/src/features/library/media_scanner.dart' as _i842;
import 'package:couch_roach/src/injection.dart' as _i481;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

extension GetItInjectableX on _i174.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    final registerModule = _$RegisterModule();
    gh.lazySingleton<_i657.ErrorLogService>(() => _i657.ErrorLogService());
    gh.lazySingleton<_i865.AppDatabase>(() => registerModule.database);
    gh.lazySingleton<_i877.LibraryRepository>(
        () => _i877.DriftLibraryRepository(gh<_i865.AppDatabase>()));
    gh.lazySingleton<_i366.StorageRepository>(
        () => _i366.DriftStorageRepository(gh<_i865.AppDatabase>()));
    gh.lazySingleton<_i883.StorageManager>(
        () => registerModule.storageManager(gh<_i366.StorageRepository>()));
    gh.lazySingleton<_i382.WatchHistoryRepository>(
        () => _i382.DriftWatchHistoryRepository(gh<_i865.AppDatabase>()));
    gh.lazySingleton<_i842.MediaScanner>(
        () => _i842.MediaScanner(gh<_i883.StorageManager>()));
    gh.lazySingleton<_i38.LibraryService>(() => _i38.LibraryService(
          gh<_i842.MediaScanner>(),
          gh<_i877.LibraryRepository>(),
          gh<_i883.StorageManager>(),
          gh<_i657.ErrorLogService>(),
        ));
    return this;
  }
}

class _$RegisterModule extends _i481.RegisterModule {}
