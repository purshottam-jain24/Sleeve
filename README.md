# Afterglow

A native macOS music companion with a cinematic Now Playing screen, synced lyrics, and an audio-reactive edge glow around your displays, coloured by the album artwork. Afterglow opens as a normal app window, and a menu bar item is available for quick control.

macOS 14+ · Apple Silicon · Swift 6 · SwiftUI + AppKit · no third-party dependencies.

## Build and run

```sh
swift test                      # unit tests
scripts/build-app.sh            # → build/Afterglow.app (ad-hoc signed)
open build/Afterglow.app        # appears in the menu bar
```

For stable privacy permissions across rebuilds, sign with a real identity:
`SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" scripts/build-app.sh`

## Permissions

| Permission | Why | When asked |
|---|---|---|
| Automation → Spotify / Music | Read artwork, position and volume; play/pause/skip/seek | The first time a running player is queried |
| System Audio Recording | Animate the edge glow from what your Mac plays | The first time an audio-reactive glow or preview needs sound |

Audio is analysed in memory only; it is never recorded, stored or uploaded. The microphone is never used.

## Documentation

- [Feasibility report](docs/01-feasibility.md): what's possible on macOS, what isn't, and why
- [Architecture](docs/02-architecture.md)
- [Roadmap and status](docs/03-roadmap.md)
- [Design system](docs/04-design-system.md)
