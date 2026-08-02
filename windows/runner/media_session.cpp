#include "media_session.h"

#include <string>
#include <variant>

#pragma warning(push, 0)
#include <systemmediatransportcontrolsinterop.h>
#include <winrt/Windows.Foundation.h>
#pragma warning(pop)

using namespace winrt::Windows::Media;

namespace {
// Button codes carried through the PostMessage marshal to the UI thread.
constexpr int kPlay = 0;
constexpr int kPause = 1;

// Read a string entry from a method call's argument map, or "" if absent.
std::string StringArg(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const char* key) {
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  if (!args) return "";
  auto it = args->find(flutter::EncodableValue(std::string(key)));
  if (it == args->end()) return "";
  const auto* value = std::get_if<std::string>(&it->second);
  return value ? *value : "";
}

// Read a bool entry from a method call's argument map, or [fallback] if absent.
bool BoolArg(const flutter::MethodCall<flutter::EncodableValue>& call,
             const char* key, bool fallback) {
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  if (!args) return fallback;
  auto it = args->find(flutter::EncodableValue(std::string(key)));
  if (it == args->end()) return fallback;
  const auto* value = std::get_if<bool>(&it->second);
  return value ? *value : fallback;
}
}  // namespace

MediaSession::MediaSession(HWND hwnd, flutter::BinaryMessenger* messenger)
    : hwnd_(hwnd) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "couch_roach/media_session",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });

  try {
    // SMTC for a plain Win32 window comes through the interop factory.
    auto interop = winrt::get_activation_factory<
        SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
    winrt::check_hresult(interop->GetForWindow(
        hwnd_, winrt::guid_of<SystemMediaTransportControls>(),
        winrt::put_abi(smtc_)));

    smtc_.IsPlayEnabled(true);
    smtc_.IsPauseEnabled(true);
    // Start closed; Dart enables it when a video actually starts playing.
    smtc_.PlaybackStatus(MediaPlaybackStatus::Closed);

    button_token_ = smtc_.ButtonPressed(
        [this](SystemMediaTransportControls const&,
               SystemMediaTransportControlsButtonPressedEventArgs const& e) {
          int code = -1;
          switch (e.Button()) {
            case SystemMediaTransportControlsButton::Play:
              code = kPlay;
              break;
            case SystemMediaTransportControlsButton::Pause:
              code = kPause;
              break;
            default:
              return;  // ignore other transport buttons
          }
          // ButtonPressed fires on a WinRT worker thread; hop to the UI thread
          // (the message loop) before touching the method channel.
          ::PostMessage(hwnd_, kButtonMessage, static_cast<WPARAM>(code), 0);
        });
    available_ = true;
  } catch (...) {
    // No SMTC available (very unlikely on desktop Windows) — degrade silently;
    // method calls become no-ops so the Dart side never errors.
    available_ = false;
  }
}

MediaSession::~MediaSession() {
  if (smtc_ && button_token_.value != 0) {
    smtc_.ButtonPressed(button_token_);
  }
}

void MediaSession::OnButtonOnUiThread(int button_code) {
  const char* name = button_code == kPlay ? "play"
                     : button_code == kPause ? "pause"
                                             : nullptr;
  if (name == nullptr) return;
  channel_->InvokeMethod(
      "onButton",
      std::make_unique<flutter::EncodableValue>(std::string(name)));
}

void MediaSession::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (!available_) {
    result->Success();  // no SMTC — succeed as a no-op
    return;
  }

  if (method == "enable") {
    smtc_.IsEnabled(true);
    auto updater = smtc_.DisplayUpdater();
    updater.Type(MediaPlaybackType::Video);
    const std::string title = StringArg(call, "title");
    if (!title.empty()) {
      updater.VideoProperties().Title(winrt::to_hstring(title));
    }
    updater.Update();
    smtc_.PlaybackStatus(MediaPlaybackStatus::Playing);
    result->Success();
  } else if (method == "setPlaybackStatus") {
    const bool playing = BoolArg(call, "playing", true);
    smtc_.PlaybackStatus(playing ? MediaPlaybackStatus::Playing
                                 : MediaPlaybackStatus::Paused);
    result->Success();
  } else if (method == "disable") {
    smtc_.PlaybackStatus(MediaPlaybackStatus::Closed);
    smtc_.IsEnabled(false);
    result->Success();
  } else {
    result->NotImplemented();
  }
}
