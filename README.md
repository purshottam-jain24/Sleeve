# Sleeve

A native macOS music companion with a cinematic Now Playing screen, synced lyrics, an audio-reactive edge glow around your displays coloured by the album artwork, and live video wallpapers. It works with Spotify, Apple Music and music in your web browser (YouTube, YouTube Music, SoundCloud and more).

macOS 14 Sonoma or later · Apple Silicon and Intel · Swift 6 · SwiftUI + AppKit · no third-party dependencies.

## Install

1. Download `Sleeve-<version>.dmg` from the [Releases](../../releases) page.
2. Open it and drag **Sleeve** into **Applications**.
3. Open Sleeve. If macOS says it can't verify the developer:
   - **macOS 15 and later:** open System Settings › Privacy & Security, scroll down and click **Open Anyway**.
   - **macOS 14:** Control-click Sleeve in Applications, choose **Open**, then **Open**.

   You only need to do this once. Builds signed with a Developer ID and notarized by Apple open without this step.

## Permissions

| Permission | Why | When asked |
|---|---|---|
| Automation → Spotify / Music | Show what's playing and power the playback buttons | The first time a running player is read |
| Automation → your browser | Find the tab that's playing and its cover art | The first time a browser plays sound |
| System Audio Recording | Sync the edge glow to the beat | Only if you turn on Edge Glow › **Follow the beat** (off by default) |

Without **Follow the beat**, Sleeve never captures audio: the glow moves gently on its own while music plays. With it on, audio is analysed in memory only. It's never recorded, saved or uploaded, and the microphone is never used.

### Music in your browser

Safari, Chrome, Arc, Brave, Edge and Vivaldi are supported. Firefox can't share tab details on macOS.

- **Out of the box:** YouTube title and cover art, and whether it's playing.
- **Full details** (artist, progress, play/pause/next/seek, and any site that publishes media info) need one browser setting:
  - **Chrome, Arc, Brave, Edge, Vivaldi:** View › Developer › **Allow JavaScript from Apple Events**
  - **Safari:** Settings › Advanced › *Show features for web developers*, then Develop › **Allow JavaScript from Apple Events**

Browsers are only queried while they're making sound, so this costs nothing the rest of the time.

## Wallpaper and lock screen

Nothing here runs unless you turn it on.

- **Live wallpaper:** import MP4 or MOV videos (or drop them on the Wallpaper screen) and click one to play it, muted and looping, behind your windows. **Turn Off** stops it and puts your own desktop picture back. Videos pause by themselves when nobody can see them: screen locked or asleep, screensaver running, behind full-screen apps, in Low Power Mode, and (by default) on battery.
- **Artwork on the lock screen:** macOS shows your desktop picture on the lock screen. With this switch on, Sleeve uses the playing song's cover as the desktop picture while music plays (a live wallpaper video steps aside meanwhile) and restores yours 20 seconds after it stops, when you turn the switch off, or when you quit. The lock screen's play, skip and timeline controls are macOS's own, for whichever app is playing; apps can't add widgets to the Mac lock screen.
- **Screensaver:** optionally installs an "Sleeve" screensaver that plays your wallpaper video, and puts your previous screensaver back when you turn it off.

If you used the standalone LiveWallpaper app, Sleeve copies its library in on first launch (as space-free APFS clones). Quit LiveWallpaper before using Sleeve's wallpaper, so the two don't both manage your desktop picture.

## Build from source

```sh
swift test                      # unit tests
scripts/build-app.sh            # → build/Sleeve.app (ad-hoc signed, Apple Silicon)
open build/Sleeve.app
```

## Make a release

```sh
scripts/make-dmg.sh             # → dist/Sleeve-<version>.dmg + .sha256 (universal, ad-hoc)
```

With an Apple Developer ID, the DMG is signed, notarized and stapled so it opens without a warning:

```sh
xcrun notarytool store-credentials sleeve --apple-id you@example.com --team-id TEAMID   # once
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=sleeve scripts/make-dmg.sh
```

The version comes from `CFBundleShortVersionString` in `Resources/Info.plist`. Regenerate the icon with `scripts/make-icon.sh`.

## Documentation

- [Feasibility report](docs/01-feasibility.md): what's possible on macOS, what isn't, and why
- [Architecture](docs/02-architecture.md)
- [Roadmap, status and energy budget](docs/03-roadmap.md)
- [Design system](docs/04-design-system.md)
