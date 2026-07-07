import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Back control for every screen except the landing page (see docs/STYLE.md).
/// Pops the nav stack; focus- and pointer-reachable like any icon button.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        if (context.canPop()) context.pop();
      },
      icon: const Icon(Icons.arrow_back_rounded),
      iconSize: 28,
      tooltip: 'Back',
    );
  }
}
