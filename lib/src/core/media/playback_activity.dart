import 'package:flutter/foundation.dart';

/// Whether a video is open in the player right now.
///
/// Background work that competes with playback consults this. The downscale
/// job is the motivating case: it encodes on the very GPU that is already
/// struggling to draw video, so running the two at once would make the thing
/// we're trying to fix worse.
///
/// A plain global (like `inputMode`) rather than a get_it service — it's read
/// from background sweeps with no `BuildContext` and set from the player's
/// lifecycle.
final ValueNotifier<bool> playbackActive = ValueNotifier<bool>(false);
