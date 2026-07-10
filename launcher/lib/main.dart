import 'dart:io';

import 'package:flutter/material.dart';

import 'updater.dart';

void main() => runApp(const LauncherApp());

class LauncherApp extends StatelessWidget {
  const LauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Couch Roach',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05060A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C7DFF),
          secondary: Color(0xFF38E1FF),
        ),
      ),
      home: const _Splash(),
    );
  }
}

class _Splash extends StatefulWidget {
  const _Splash();

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> {
  UpdateStatus _status =
      const UpdateStatus(UpdatePhase.checking, message: 'Starting…');

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final launched = await Updater().run((s) {
      if (mounted) setState(() => _status = s);
    });
    // App launched → the launcher's job is done; let the splash linger briefly
    // so the window doesn't vanish mid-blink, then exit.
    if (launched != null && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isError = _status.phase == UpdatePhase.error;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Couch Roach',
                    style: text.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 28),
                if (isError)
                  _ErrorBody(message: _status.message)
                else
                  _ProgressBody(status: _status),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressBody extends StatelessWidget {
  const _ProgressBody({required this.status});
  final UpdateStatus status;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final fraction = status.fraction;
    return Column(
      children: [
        SizedBox(
          width: 320,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: status.phase == UpdatePhase.downloading ? fraction : null,
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          status.phase == UpdatePhase.downloading && fraction != null
              ? '${status.message}  ${(fraction * 100).round()}%'
              : status.message,
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: const Color(0xFFAAB1CC)),
        ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        const Icon(Icons.error_outline_rounded,
            color: Color(0xFFFF5C7A), size: 36),
        const SizedBox(height: 16),
        SelectableText(
          message,
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: const Color(0xFFAAB1CC)),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => exit(1),
          child: const Text('Quit'),
        ),
      ],
    );
  }
}
