import 'package:flutter/services.dart';

/// Whether [key] is one of the OS media play/pause keys.
///
/// Keyboards and remotes disagree about which of the three they emit, so all
/// are treated the same.
bool isMediaPlayPauseKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.mediaPlayPause ||
    key == LogicalKeyboardKey.mediaPlay ||
    key == LogicalKeyboardKey.mediaPause;

/// Whether the player should **swallow** a raw key event instead of letting it
/// reach media_kit's controls.
///
/// The player observes keys globally (not through a focus node) so a remote
/// reveals the overlay without stealing play/pause or arrow-seek from the
/// controls — so the answer is almost always "no, pass it through".
///
/// The exception is the media play/pause key on Windows, where the SMTC session
/// already delivers the press as a media-session button and acts on it. Letting
/// the raw key through as well would make media_kit toggle a second time and
/// the two would cancel out, leaving playback unchanged. Platforms without SMTC
/// have no such duplicate, so they must keep passing it through — swallowing it
/// there would break play/pause outright.
bool shouldSwallowKey(LogicalKeyboardKey key, {required bool hasMediaSession}) =>
    hasMediaSession && isMediaPlayPauseKey(key);
