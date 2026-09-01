import 'package:flutter/material.dart';

import '../core/input/input_mode.dart';
import '../theme/theme.dart';

/// The standard interactive surface for the 10-foot UI. Works with **both**
/// input modes (the remote acts like a mouse) and keeps a **single** selection
/// across them: hovering a card moves keyboard focus onto it, so the mouse and
/// the D-pad share one highlight. Fires [onPressed] on Enter/Space **or** click,
/// and scrolls a keyboard-focused card into view. See docs/STYLE.md.
///
/// Hover moves the selection **only in pointer mode** ([InputMode]). Once the
/// user starts arrow-navigating (keyboard mode), incidental cursor drift — the
/// remote is an air-mouse — is ignored, so the highlight isn't yanked away; a
/// deliberate click switches back to pointer mode (and selects the card).
class FocusableCard extends StatefulWidget {
  const FocusableCard({
    super.key,
    required this.child,
    this.onPressed,
    this.onContextAction,
    this.borderRadius = AppRadii.rLg,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback? onPressed;

  /// Optional secondary action — fired on long-press (remote/touch) or
  /// right-click (pointer). Used for a context menu like "Not interested".
  final VoidCallback? onContextAction;
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
    // Skip it only when the focus came from the mouse hovering the card (pointer
    // mode) — it's already under the cursor, and centering it would yank it
    // away. In keyboard mode always center it, even if the cursor happens to
    // rest over it.
    final fromHover = _hovered && inputMode.isPointer;
    if (value && !fromHover && Scrollable.maybeOf(context) != null) {
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
    // Hovering makes this card the one selection — but only in pointer mode.
    // In keyboard mode the cursor may be resting over (or drifting across)
    // cards while the user arrow-navigates; letting that steal focus is exactly
    // the erratic behavior we're fixing. A click flips back to pointer mode.
    if (value && inputMode.isPointer && !_node.hasFocus) _node.requestFocus();
  }

  void _onTap() {
    // A click is a deliberate select: the app-level pointer listener has already
    // flipped to pointer mode, so move the highlight here, then activate.
    _node.requestFocus();
    widget.onPressed?.call();
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
        onTap: widget.onPressed == null ? null : _onTap,
        onLongPress: widget.onContextAction,
        onSecondaryTap: widget.onContextAction,
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
