/// The fixed output texture size to render a video into for a given height cap,
/// or null when uncapped.
///
/// Why this exists: on a box where libmpv can't hand GPU surfaces to the
/// renderer (`hwdec-interop` empty, so decode falls back to a `-copy` variant),
/// every frame is read back to system memory and re-uploaded to draw. At 4K
/// 10-bit that saturates the output stage and frames get dropped at
/// presentation — `frame-drop-count` climbs while `decoder-frame-drop-count`
/// stays at zero. Rendering into a smaller texture cuts the upload-and-draw
/// half of that cost.
///
/// A 16:9 box at the cap height bounds **any** aspect ratio, because mpv
/// preserves aspect and letterboxes into whatever size it's given: a 2:1 4K
/// film capped at 1080 renders 1920x960 instead of 3840x1920 — a quarter of the
/// pixels.
///
/// Note this caps the *output* only. The readback happens at the decoded
/// resolution regardless, so this reduces the bottleneck rather than removing
/// it. It also means a source *smaller* than the cap is rendered into a larger
/// texture than it needs (a 720p file into a 1080p box), which is why the cap
/// is opt-in rather than on by default. Pure + tested.
({int width, int height})? videoOutputCap(int maxHeight) {
  if (maxHeight <= 0) return null; // 0 / negative → uncapped
  return (width: (maxHeight * 16 / 9).round(), height: maxHeight);
}
