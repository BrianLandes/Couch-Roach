import 'package:flutter/material.dart';

/// M1 placeholder landing screen. Will become the two-rail landing
/// (Continue Watching + For You) in M2. For now it's the app shell entry point
/// and a home for the library grid once the scanner is wired to the DB.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Couch Roach',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Home Media Center',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            const Text('M1 scaffold — library scan + player next.'),
          ],
        ),
      ),
    );
  }
}
