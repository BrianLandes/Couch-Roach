/// Compose the fullest playback title for a TV episode from its parts: the show
/// name, the `SxxExx` code, and the episode name — dropping each trailing piece
/// when it isn't known. e.g. "Game of Thrones — S01E03 · Winter Is Coming", or
/// "Game of Thrones — S01E03" when the episode name is unknown. With no season /
/// episode (a movie), returns the bare [name]. Pure + tested.
String composePlayerTitle({
  required String name,
  int? season,
  int? episode,
  String? episodeName,
}) {
  if (season == null || episode == null) return name;
  final code = 'S${_pad(season)}E${_pad(episode)}';
  final ep = episodeName?.trim();
  return (ep != null && ep.isNotEmpty) ? '$name — $code · $ep' : '$name — $code';
}

String _pad(int n) => n.toString().padLeft(2, '0');
