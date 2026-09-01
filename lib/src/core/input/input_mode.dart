import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Which input device is currently driving selection in the 10-foot UI.
///
/// The remote doubles as an air-mouse, so a resting hand jitters the cursor.
/// Without a mode, that incidental movement hijacks the arrow-key selection —
/// hover-to-focus fires on cursor drift and yanks the highlight out from under
/// the D-pad. The app tracks an explicit mode instead:
///
/// * pressing a D-pad/arrow (or Tab) key enters [keyboard] mode, where hover is
///   ignored and selection moves only via the keyboard;
/// * a **deliberate** pointer action — a click or a scroll, never mere movement
///   — enters [pointer] mode, where hovering a card selects it as before.
enum InputMode { keyboard, pointer }

/// App-wide current [InputMode]. Read synchronously inside hot input callbacks
/// (e.g. `FocusableCard`'s hover handler), so it's a plain global rather than a
/// get_it service or a Riverpod provider — no `BuildContext`, no async. It's a
/// [ValueNotifier], so widgets that want to react (e.g. hide the cursor in
/// keyboard mode) can listen.
class InputModeController extends ValueNotifier<InputMode> {
  InputModeController() : super(InputMode.pointer);

  bool get isKeyboard => value == InputMode.keyboard;
  bool get isPointer => value == InputMode.pointer;

  /// A selection-moving key (arrows / Tab / D-pad) was pressed → keyboard mode.
  void onKeyboardNav() => value = InputMode.keyboard;

  /// A deliberate pointer action (click / scroll) happened → pointer mode.
  /// Cursor *movement* alone must never call this.
  void onPointerAction() => value = InputMode.pointer;
}

/// The single app-wide instance.
final inputMode = InputModeController();

/// Logical keys that move the selection. Enter/Space *activate* the current
/// selection but don't move it, so they don't force a switch — they work in
/// either mode and leave the mode as-is.
const _navKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.tab,
};

/// Global [HardwareKeyboard] handler that flips to keyboard mode on a nav key.
/// Register once in `main()` via `HardwareKeyboard.instance.addHandler`. Always
/// returns `false` so it never consumes the event — focus traversal still runs.
bool inputModeKeyHandler(KeyEvent event) {
  if (event is KeyDownEvent && _navKeys.contains(event.logicalKey)) {
    inputMode.onKeyboardNav();
  }
  return false;
}
