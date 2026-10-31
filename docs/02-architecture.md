# Afterglow — Architecture

## Module graph

```
                 ┌──────────────────────────────┐
                 │  Afterglow (executable, UI)  │  SwiftUI + AppKit
                 │  DesignSystem · Modes ·      │
                 │  MenuBar · Settings · System │
                 └──────┬──────────┬────────────┘
                        │          │
             ┌──────────▼───┐  ┌───▼───────────┐
             │ AfterglowGlow│  │ AfterglowAudio│
             │ EdgeGlow*    │──▶ Capture +     │
             └──────┬───────┘  │ Analyzer      │
                    │          └───────────────┘
             ┌──────▼──────────────────────────┐
             │ AfterglowCore                   │
             │ Models · Settings · Music ·     │
             │ Artwork · Lyrics · Keychain     │
             └─────────────────────────────────┘
```

`AfterglowCore` has no UI dependencies beyond AppKit image types. Each module is unit-tested on its own.

## Folder structure

```
Package.swift
Resources/                      Info.plist, Afterglow.entitlements
scripts/build-app.sh            SwiftPM product → signed Afterglow.app
docs/
Sources/
  AfterglowCore/
    Models/                     Track, PlaybackSnapshot, AppSettings, GlowSettings, RGBAColor
    Settings/SettingsManager    JSON persistence in Application Support, debounced saves
    Music/
      MusicProvider             protocol (dependency-injected)
      AppleScriptRunner         serial-queue Apple Events with typed errors
      SpotifyService            local Spotify provider
      AppleMusicService         Music.app provider
      MusicSourceManager        registry, running state, source priority
      NowPlayingService         active snapshot, interpolated position, artwork and palette pipeline
    Artwork/
      ArtworkColorExtractor     palette extraction (pure, tested)
    Lyrics/                     (Phase 5) LyricsService, LRC parser, LRCLIB provider
    Support/                    logging, Keychain (Phase 3b)
  AfterglowAudio/
    AudioCaptureService         backend selection, lifecycle, permission state
    ProcessTapCapture           Core Audio process tap (14.2+)
    ScreenCaptureAudioCapture   ScreenCaptureKit fallback (14.0–14.1)
    AudioSampleBuffer           lock-protected ring buffer (written on the real-time thread)
    AudioAnalyzer               vDSP FFT → level/bass/mid/treble/beat/spectrum (pure, tested)
  AfterglowGlow/
    GlowAnimator                settings + audio + time → GlowFrame (pure, tested)
    GlowGeometry                perimeter path with corner radius and notch handling
    GlowMaskRenderer            cached, low-resolution blurred alpha masks
    EdgeGlowView                4 composited layers, display-link driven
    EdgeGlowRenderer            one overlay window per selected display, screen-change handling
  Afterglow/
    App/                        @main, AppEnvironment (composition root), lifecycle
    DesignSystem/               tokens, Surface (glass or material), components
    MenuBar/                    MenuBarManager panel
    Modes/                      (Phase 2) FloatingPlayer, Cinematic, Lyrics, DesktopWidget
    Settings/                   preferences window
    System/                     LaunchAtLogin, PowerObserver, HotKeys
Tests/
  AfterglowCoreTests  AfterglowAudioTests  AfterglowGlowTests
```

## Mapping to the requested modules

| Requested | Implementation |
|---|---|
| MusicSourceManager, NowPlayingService, SpotifyService, AppleMusicService | `AfterglowCore/Music` |
| LyricsService | `AfterglowCore/Lyrics` (Phase 5) |
| ArtworkColorExtractor | `AfterglowCore/Artwork` |
| AudioCaptureService, AudioAnalyzer | `AfterglowAudio` |
| EdgeGlowRenderer | `AfterglowGlow` |
| FloatingPlayerManager, DesktopWidgetManager | `Afterglow/Modes` (Phase 2) |
| ThemeManager | `Afterglow/DesignSystem` |
| SettingsManager | `AfterglowCore/Settings` |
| MenuBarManager | `Afterglow/MenuBar` |

## Key decisions

- **Concurrency:** Swift 6 strict concurrency. All observable state lives on `@MainActor`. Real-time audio threads only touch `AudioSampleBuffer`, a lock-protected type that does no allocation. Apple Events run on one serial dispatch queue, never on the main thread.
- **Dependency injection:** `MusicSourceManager` takes `[any MusicProvider]`. Tests and future providers (Spotify Web API, others) plug in without UI changes.
- **Failure isolation:** every provider call returns typed errors, and the UI renders each source's own status. A failed audio capture leaves the glow running in its non-audio idle behaviour, and the rest of the app is unaffected.
- **Energy:**
  - Playback position is interpolated locally, with a resync every 5 seconds only while playing.
  - The glow display link stops completely for static presets and when the glow is hidden.
  - Audio capture runs only when the glow is enabled *and* the active preset uses audio.
- **Settings storage:** settings live in a single Codable JSON document. Every field decodes with a fallback, so schema changes never wipe user settings. This replaces SwiftData because the data is one small document, not a relational store. A cache (lyrics, artwork) will use the file system with size limits.
