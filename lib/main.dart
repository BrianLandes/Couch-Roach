import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize libmpv (media_kit) before any player is created.
  MediaKit.ensureInitialized();

  runApp(const CouchRoachApp());
}
