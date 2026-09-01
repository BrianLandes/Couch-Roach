// Pure audio-track selection logic, decoupled from media_kit's `AudioTrack` so
// it's unit-testable without a player. The player maps its real tracks onto
// [AudioTrackInfo] and applies the chosen index.

/// The minimal view of an audio track the auto-select needs.
class AudioTrackInfo {
  const AudioTrackInfo({
    this.language,
    this.title,
    this.channels = 0,
    this.isDefault = false,
  });

  /// Language tag as libmpv reports it ('en', 'eng', 'English', …); null if the
  /// container doesn't tag it.
  final String? language;

  /// Human title the container carries ('English 5.1', 'Director commentary'…).
  final String? title;

  /// Channel count; 0 when libmpv hasn't probed it yet.
  final int channels;

  /// True for the track the container marks as its default.
  final bool isDefault;
}

/// Whether [t] is an English audio track — by language tag or an English-named
/// title (some rips leave the language blank but name the track).
bool isEnglishAudio(AudioTrackInfo t) {
  final lang = (t.language ?? '').toLowerCase().trim();
  final title = (t.title ?? '').toLowerCase();
  return lang == 'en' ||
      lang == 'eng' ||
      lang.startsWith('english') ||
      title.contains('english');
}

/// The index of the audio track to auto-select, or null to leave libmpv's own
/// default alone. Language beats channel width: an **English** track is
/// preferred over any other language, so English stereo wins over a foreign
/// 5.1. Within the chosen language group the widest layout wins when
/// [preferSurround] is on; ties keep the container's default.
///
/// Returns null when there's nothing worth switching to: fewer than two tracks,
/// or no English track and [preferSurround] is off (so we don't reorder purely
/// for channels against the user's wish). Pure + tested.
int? autoAudioTrackIndex(
  List<AudioTrackInfo> tracks, {
  required bool preferSurround,
}) {
  if (tracks.length < 2) return null;

  final english = [
    for (var i = 0; i < tracks.length; i++)
      if (isEnglishAudio(tracks[i])) i,
  ];

  final List<int> pool;
  if (english.isNotEmpty) {
    pool = english;
  } else if (preferSurround) {
    pool = [for (var i = 0; i < tracks.length; i++) i];
  } else {
    return null;
  }

  var best = pool.first;
  for (final i in pool.skip(1)) {
    final a = tracks[best];
    final b = tracks[i];
    if (preferSurround && a.channels != b.channels) {
      if (b.channels > a.channels) best = i;
    } else if (a.isDefault != b.isDefault) {
      if (b.isDefault) best = i;
    }
    // Otherwise keep the earlier track (stable — no needless reordering).
  }
  return best;
}

/// A short, readable channel layout name for a track label, or null when the
/// count is unknown.
String? channelLayoutLabel(int channels) => switch (channels) {
      0 => null,
      1 => 'Mono',
      2 => 'Stereo',
      6 => '5.1',
      8 => '7.1',
      _ => '${channels}ch',
    };

/// The channel count for a track, given the two fields libmpv can report it in.
/// They don't always agree (and either can be absent), so take the wider — a
/// track that reports 6 in one field and 0 in the other is 5.1, not unknown.
int audioChannelCount({int? channelsCount, int? audioChannels}) {
  final a = channelsCount ?? 0;
  final b = audioChannels ?? 0;
  return a > b ? a : b;
}

/// A readable label for an audio track in the right-click picker — its title or
/// language, plus the channel layout ("English (ENG) · 5.1", "PT · Stereo",
/// "Track 2"). Pure; the widget passes the raw libmpv fields straight through.
///
/// The language is only appended when the title doesn't already say it, so a
/// track titled "English 5.1" doesn't come out as "English 5.1 (ENG)".
String audioTrackLabel({
  required String id,
  String? title,
  String? language,
  int channels = 0,
}) {
  final t = title?.trim();
  final lang = language?.trim();
  final bits = <String>[];
  if (t != null && t.isNotEmpty) {
    bits.add(t);
    if (lang != null &&
        lang.isNotEmpty &&
        !t.toLowerCase().contains(lang.toLowerCase())) {
      bits.add('(${lang.toUpperCase()})');
    }
  } else if (lang != null && lang.isNotEmpty) {
    bits.add(lang.toUpperCase());
  } else {
    bits.add('Track $id');
  }
  final ch = channelLayoutLabel(channels);
  if (ch != null) bits.add('· $ch');
  return bits.join(' ');
}

/// Whether an audio track id is a real, selectable track rather than one of
/// libmpv's synthetic "auto"/"no" entries, which must never appear in the menu.
bool isSelectableTrackId(String id) => id != 'auto' && id != 'no';
