import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// The standard interactive surface for the 10-foot UI. Works with **both**
/// input modes (the remote acts like a mouse) and keeps a **single** selection
/// across them: hovering a card moves keyboard focus onto it, so the mouse and
/// the D-pad share one highlight. Mousing over a card overrides whatever the
/// arrow keys had selected, and the arrows then pick up from where the mouse
/// last was. Fires [onPressed] on Enter/Space **or** click, and scrolls a
/// keyboard-focused card into view. See docs/STYLE.md.
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
  final FocusNode _node = FocusNode();
  bool _focused = false;
  // Whether the pointer is currently over this card — used only to distinguish
  // hover-driven focus from keyboard focus (so hovering doesn't scroll the card
  // out from under the cursor). The highlight itself is driven by focus alone,
  // so there's exactly one selected card at a time.
  bool _hovered = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _onFocusHighlight(bool value) {
    if (!mounted) return;
    // Scroll a *keyboard*-focused card fully into view (focus follows scroll).
    // Skip it when the focus came from the mouse hovering the card — it's
    // already under the cursor, and centering it would yank it away.
    if (value && !_hovered && Scrollable.maybeOf(context) != null) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
    setState(() => _focused = value);
  }

  void _onHoverHighlight(bool value) {
    _hovered = value;
    // Hovering makes this card the one selection: pull keyboard focus here so
    // the mouse and arrow keys share a single highlight, and the arrows then
    // continue from where the mouse last was. Focus stays put when the pointer
    // leaves, so moving the mouse off a card doesn't clear the selection.
    if (value && !_node.hasFocus) _node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: _node,
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: _onFocusHighlight,
      onShowHoverHighlight: _onHoverHighlight,
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
              color: _focused ? AppColors.focus : Colors.transparent,
              width: 2,
            ),
            boxShadow: _focused
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
