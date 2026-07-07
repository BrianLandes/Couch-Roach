import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app.dart';
import 'src/core/storage/storage_manager.dart';
import 'src/injection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize libmpv (media_kit) before any player is created.
  MediaKit.ensureInitialized();

  // Wire the DI container (services/singletons — see lib/src/injection.dart).
  configureDependencies();

  // Hydrate the configured storage roots so scanning/placement see every disk.
  await getIt<StorageManager>().load();

  runApp(const ProviderScope(child: CouchRoachApp()));
}
