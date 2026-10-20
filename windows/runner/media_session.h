#ifndef RUNNER_MEDIA_SESSION_H_
#define RUNNER_MEDIA_SESSION_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

// Suppress warnings from the Windows SDK's C++/WinRT headers (the runner builds
// with /W4 /WX; those headers aren't warning-clean under it).
#pragma warning(push, 0)
#include <winrt/Windows.Media.h>
#pragma warning(pop)

// Bridges the app's playback to the Windows System Media Transport Controls
// (SMTC). Owning an SMTC session makes Couch Roach the OS "current media", so the
// hardware Play/Pause key routes here instead of leaking to Spotify/YouTube in
// the background. The C++ side owns the session for a window; the Dart side
// enables it while a video plays, keeps the playback status in sync, and receives
// the OS button presses over a method channel ("couch_roach/media_session").
class MediaSession {
 public:
  MediaSession(HWND hwnd, flutter::BinaryMessenger* messenger);
  ~MediaSession();

  // Custom window message posted from the (background-thread) SMTC callback so
  // the method-channel call is made on the UI/platform thread. wparam is the
  // button code.
  static constexpr UINT kButtonMessage = WM_APP + 0x51;

  // Invoked by the window proc when kButtonMessage arrives (UI thread): forwards
  // the button to Dart.
  void OnButtonOnUiThread(int button_code);

  // Handles a WM_APPCOMMAND (UI thread). A media key whose WM_KEYDOWN lands on
  // the top-level window rather than the Flutter view (focus can sit there
  // after a fullscreen switch) never reaches the framework; DefWindowProc turns
  // it into WM_APPCOMMAND and, unhandled, the shell forwards it to whichever
  // app it considers current — a background Spotify/YouTube. While a video is
  // up we claim it instead: forward it to Dart and return true so the window
  // proc reports it handled and the shell never sees it.
  bool HandleAppCommand(int command);

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  HWND hwnd_;
  bool available_ = false;
  // Between "enable" and "disable" — i.e. while the player is on screen.
  bool active_ = false;
  winrt::Windows::Media::SystemMediaTransportControls smtc_{nullptr};
  winrt::event_token button_token_{};
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_MEDIA_SESSION_H_
