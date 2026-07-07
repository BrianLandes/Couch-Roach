import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// The standard interactive surface for the 10-foot UI. Works with **both**
/// input modes (the remote acts like a mouse): it highlights on keyboard/D-pad
/// focus **or** pointer hover, and fires [onPressed] on Enter/Space **or** click.
/// When it gains focus it scrolls itself fully into view. See docs/STYLE.md.
class FocusableCard extends StatefulWidget {
  const FocusableCard({
    super.key,
    required this.child,
    this.onPressed,
    this.borderRadius = AppRadii.rLg,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final BorderRadius borderRadius;
  final bool autofocus;

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard> {
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered;

  void _onFocusHighlight(bool value) {
    if (!mounted) return;
    if (value && Scrollable.maybeOf(context) != null) {
      // Keep the newly-selected item fully on screen (focus follows scroll).
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
    setState(() => _focused = value);
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: _onFocusHighlight,
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            // Reserve the ring's 2px always (transparent) so focus never shifts layout.
            border: Border.all(
              color: _active ? AppColors.focus : Colors.transparent,
              width: 2,
            ),
            boxShadow: _active
                ? const [
                    BoxShadow(
                      color: AppColors.focusGlow,
                      blurRadius: 26,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
