# Sleeve — Implementation Roadmap

Each phase ends with `swift build`, `swift test`, and a manual check of the bundled app. Status markers are only updated once that check passes.

| Phase | Scope | Exit criteria | Status |
|---|---|---|---|
| **1. Feasibility and foundation** | Feasibility report, architecture, design system spec, SwiftPM package, `.app` bundling script, settings persistence, menu bar app shell | Builds and launches as a menu bar agent; settings persist across relaunch | ✅ Done |
| **3. Music integration** *(pulled forward: everything depends on it)* | Spotify and Music providers, notifications plus scripted enrichment, controls, seek/volume, source priority, artwork, palette | Track changes in Spotify and Music show within 1 s; controls work; denying Automation degrades without breaking | Built and unit-tested; live test with the players pending |
| **4. Edge Glow engine** | Layered overlay, notch handling, multi-display support, process-tap capture plus ScreenCaptureKit fallback, FFT analyzer, 6 presets, custom presets, artwork colours | Glow is stable at 60 FPS on a ProMotion display; low idle CPU; reacts to Spotify, Music and browser audio | Rendering verified; idle CPU ≈1 % animating, 0 % static; live audio capture pending |
| **2a. Main app window** | Window on launch, sidebar, Now Playing, Glow Studio with live engine previews, Sources, Settings | Opens on launch; previews run the real engine | ✅ Done |
| **2b. Modes and themes** | Mode 1 Floating, Mode 4 Desktop Widget, floating lyrics overlay; themes (Apple Minimal, Liquid Glass, Cinematic, Custom) | All themes × modes render correctly; every control is functional | Next |
| **5. Lyrics** | LRCLIB provider, LRC + word-timed parser, Focus/Karaoke/Glow styles, click-to-seek, per-song offset, search, on-device translation (macOS 15+) | Lyrics stay in sync within ±150 ms after offset adjustment; "no lyrics" state is never faked | Built and unit-tested; live sync check with a playing song pending |
| **3b. Spotify Web API** | PKCE OAuth, Keychain, token refresh, Connect devices | Connect/disconnect/refresh are tested; no secrets in the repo | |
| **6. macOS integration** | Global hotkeys, launch at login, start minimized, sleep/wake hardening, display hot-plug | Survives sleep/wake and monitor unplug without leaked windows or taps | |
| **7. Release** | Developer ID signing, notarization, DMG script, performance pass in Instruments, memory checks | Notarized DMG installs cleanly on macOS 14 and the current release | |

## Test matrix for phase exits

- **Players:**
  - Spotify running or not running
  - Music running or not running
  - both playing
  - neither playing
  - Automation denied
- **Audio:**
  - permission granted or denied
  - output device switched (for example, to AirPods) mid-playback
  - output muted
- **Displays:**
  - single display, built-in notched display
  - external display plus the laptop
  - lid closed
  - resolution change
  - display unplugged while glowing
- **Power:** sleep and wake, Low Power Mode
- **Full-screen apps:** glow appears over full-screen Safari and Keynote; exclusive-capture games are known exceptions

## Energy budget (measured, Apple Silicon, release build)

| State | CPU (Sleeve process) |
|---|---|
| Window open, glow off | ≈0% |
| Glow on, nothing playing (any preset, any idle behaviour) | ≈0%: frame loop stops; idle breathing runs as a Core Animation animation |
| Glow on, music playing, per-frame engine work | ≈0.07 ms/frame (≈0.4% of a core at 60 fps), plus Core Animation commit |

Rules that keep it there:
- No SwiftUI-driven perpetual animations. Ambient motion is Core Animation, which runs in the render server.
- Nothing polls on a timer while paused. Lyrics wake only at line boundaries; the glow loop pauses when settled.
- System audio is captured only while Spotify or Music is playing, unless "React to all apps' audio" is on.
- Previews stop when their window is hidden, and preset cards render at 24 fps.
- Observable state is never rewritten with an unchanged value. A binding doing this caused a 100% CPU feedback loop.
