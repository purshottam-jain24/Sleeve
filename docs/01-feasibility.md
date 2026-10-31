# Afterglow — Technical Feasibility Report

Verified on: Apple Silicon (arm64), macOS 27.2, Xcode 27.2, macOS SDK 27.2, Swift 6.4.2.
Deployment target: **macOS 14.0**.

Every claim below is marked as one of:

- **Verified (SDK):** the symbol exists and type-checks against the installed SDK with a macOS 14 target.
- **Verified (runtime):** exercised on this machine.
- **Documented:** public Apple/vendor documentation or long-standing, widely relied-on behaviour that has not been re-tested here.
- **Risk:** private, undocumented, or likely to change.

---

## 1. Now Playing detection

| Approach | Status | Decision |
|---|---|---|
| `MediaRemote.framework` (`MRMediaRemoteGetNowPlayingInfo`) | **Risk.** Private framework. Since macOS 15.4, now-playing data is reported to be withheld from processes without an Apple entitlement. A probe here returned `nil`, but no audio was playing, so the result is inconclusive. | **Not used.** We never ship private-API dependencies for core features. |
| Distributed notifications — `com.spotify.client.PlaybackStateChanged`, `com.apple.Music.playerInfo` | **Documented.** Both apps post these when the state changes. Payload: state, title, artist, album, duration, and track ID; Spotify also sends the position. No permission is needed. | **Primary push signal.** |
| AppleScript / Apple Events to Spotify and Music | **Documented.** Gives state, position, volume, and artwork (Spotify sends an artwork URL; Music sends raw artwork data). Needs `NSAppleEventsUsageDescription`, and the user is asked once per app for Automation permission. | **Used for enrichment and control.** If the user denies Automation, the app still shows track info from notifications, but controls and artwork are disabled with a clear explanation. |
| MusicKit `SystemMusicPlayer` | **Verified (SDK):** `@available(macOS, unavailable)`. | Not possible on macOS. |
| MusicKit `ApplicationMusicPlayer` | Available on macOS 14, but it plays inside *our* app; it does not observe Music.app. | Not relevant for a companion app. |

**Other players.** Browsers, VLC, and similar players have no public now-playing API on modern macOS. Edge Glow still reacts to their audio, because system audio capture is source-agnostic. Their metadata will show as "Unsupported player" until a public API exists. **This is a documented limitation, not a TODO.**

Important guard: an Apple Event sent to an app that isn't running *launches* it. Every scripted call is therefore gated on `NSRunningApplication` first.

## 2. Spotify

- **Local (AppleScript and notifications):** covers now playing, artwork URL, play/pause/next/previous, seek, and volume. No account or network connection is needed.
- **Spotify Web API (OAuth Authorization Code + PKCE):** this is optional and comes in a later phase. It adds Spotify Connect playback on other devices and higher-resolution artwork. PKCE needs no client secret, so no secret is ever shipped. Tokens go in the Keychain, and refresh tokens are rotated. Limitation: Spotify apps in "development mode" are restricted to an allow-list of users. Wide distribution needs a Spotify quota extension.

## 3. Apple Music

Music.app is controlled through AppleScript only (see §1). Artwork comes from `raw data of artwork 1 of current track`. Some streaming and radio items expose no artwork or duration; the app treats both as optional.

## 4. System audio capture (Edge Glow)

| API | Availability | Permission | Decision |
|---|---|---|---|
| Core Audio **process taps** (`CATapDescription` + `AudioHardwareCreateProcessTap` + private aggregate device) | **Verified (SDK):** macOS 14.2+ | "System Audio Recording" (`NSAudioCaptureUsageDescription`). Narrower than Screen Recording. | **Primary backend.** A global stereo tap that excludes our own process. |
| ScreenCaptureKit `SCStreamConfiguration.capturesAudio` | **Verified (SDK):** macOS 13+ | Screen Recording (broader, so it's a harder sell to users) | **Fallback for macOS 14.0–14.1 only.** |
| Microphone | — | Microphone | **Never used.** |

Privacy guarantees, enforced in code: samples go into a fixed-size in-memory ring buffer (about 4,096 frames). The app only reads summary features from it (levels, bands, beats). Nothing is written to disk or sent over the network.

Note: there is no public API to *query* the System Audio Recording permission state. If capture fails, or the tap delivers nothing but digital silence while a player reports "playing", the UI shows "Audio access may be blocked" and a button that opens the correct System Settings pane.

## 5. Overlay windows and displays

- **Edge Glow overlay:** one borderless, transparent, click-through window per display (`ignoresMouseEvents = true`), at `.screenSaver` level, with `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`. The app is an agent app (`LSUIElement`), which lets these windows appear over other apps' full-screen Spaces.
- **What we do *not* promise:** the glow is **not** guaranteed to appear above:
  - the login window and screen lock
  - Mission Control and other system transitions
  - apps that capture a display exclusively (some games use `CGDisplayCapture`)
  - DRM-protected video surfaces, which may be composited differently

  This is documented in the UI.
- **Frame timing:** `NSView.displayLink(target:selector:)` (**Verified (SDK)**, macOS 14). It is tied to each window's display, pauses automatically when the display sleeps, and respects ProMotion `preferredFrameRateRange`.
- **Notch:** `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (macOS 12+) give the exact notch rectangle. The glow can *wrap* around the notch, leave a *gap*, or *ignore* it.
- **Display changes:** `NSApplication.didChangeScreenParametersNotification` causes windows to be rebuilt for each display. `NSWorkspace` sleep and wake notifications pause and resume audio capture.

## 6. Liquid Glass

`NSGlassEffectView` and SwiftUI `.glassEffect(_:in:)` are **Verified (SDK)** for macOS 26+. On macOS 14 and 15 the design system falls back to `NSVisualEffectView` materials (`.hudWindow` / `.popover`) with a hairline highlight. One modifier (`.surface(...)`) hides this branch from feature code.

## 7. Desktop widget

WidgetKit widgets cannot show live, sub-second playback progress or drive the edge-glow pipeline, and they need an app extension. Mode 4 is therefore a **desktop-level `NSPanel`**: below normal windows, above desktop icons, on all Spaces, with optional always-on-top. A WidgetKit extension can be added later as a separate deliverable.

## 8. Lyrics

**Verified (runtime):** LRCLIB (`https://lrclib.net/api/get`) returns `syncedLyrics` (LRC), `plainLyrics`, and `instrumental` for title, artist, album, and duration lookups. It is free, needs no key, and asks clients to send an identifying User-Agent.

- When nothing is found, the app says so. It never fabricates lyrics.
- Translations depend on whether a source supplies them. LRCLIB does not. On macOS 15+, Apple's on-device Translation framework is a candidate, to be checked in Phase 5.
- **Licensing caveat:** lyrics are copyrighted. LRCLIB content is community-contributed. Commercial distribution should be reviewed with counsel, or should switch to a licensed provider such as Musixmatch. The `LyricsProvider` protocol keeps that swap isolated.

## 9. Distribution and entitlements

- **Not sandboxed.** Apple Events to arbitrary players and process taps work best outside the App Sandbox, so the app ships through Developer ID with notarization, not the Mac App Store.
- **Hardened runtime entitlement:** `com.apple.security.automation.apple-events`.
- **Info.plist:** `LSUIElement`, `NSAppleEventsUsageDescription`, `NSAudioCaptureUsageDescription`, and `NSScreenCaptureUsageDescription` (for the 14.0–14.1 fallback).
- **Launch at login:** `SMAppService.mainApp` (**Verified (SDK)**). It only works from a real `.app` bundle.
- **Global keyboard shortcuts:** Carbon `RegisterEventHotKey` (public and needs no permission). No Accessibility permission is required.

## 10. Build system

The repo started empty, and XcodeGen and Tuist are not installed. The project is a **Swift package**: library targets per module, one executable target, and test targets. `scripts/build-app.sh` assembles a signed `.app` bundle (Info.plist and entitlements) from the SwiftPM product. This avoids a hand-edited `.xcodeproj`. `swift build` and `swift test` work on the command line. An Xcode project can be generated later for archive and notarize workflows if preferred.

## 11. Intel support

There is no Apple-Silicon-only API in the design. Accelerate/vDSP, Core Audio, and Core Animation are universal. Building with `--arch arm64 --arch x86_64` produces a universal binary, but this is untested.
