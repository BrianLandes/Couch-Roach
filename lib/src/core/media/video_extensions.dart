/// File extensions treated as playable video. Single source of truth shared by
/// the library scanner (which files to index) and the torrent daemon (which file
/// in a torrent is the primary video). Lowercase, dot-prefixed.
const Set<String> kVideoExtensions = {
  '.mkv', '.mp4', '.avi', '.mov', '.m4v', '.webm', '.ts', '.wmv', '.flv',
};
