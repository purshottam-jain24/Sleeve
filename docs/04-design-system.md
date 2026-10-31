# Sleeve — Design System

## Principles

1. **Artwork is the hero.** Colour, light, and atmosphere come from the album. Chrome stays neutral.
2. **Native first.** Use SF Pro, SF Symbols, system materials, and standard control metrics. Never fight macOS.
3. **Light, not decoration.** Gradients only come from artwork or glow. There are no ornamental gradients on surfaces.
4. **Quiet motion.** Every animation has a purpose: a state change, a track change, or a response to audio. Nothing loops just to look busy.

## Tokens

### Corner radii (continuous)
| Token | Value | Use |
|---|---|---|
| `radius.xs` | 6 | small artwork thumbnails, chips |
| `radius.sm` | 10 | buttons, list rows |
| `radius.md` | 14 | artwork in compact player |
| `radius.lg` | 20 | panels, floating player, widget |
| `radius.xl` | 28 | cinematic artwork |

### Spacing (4-pt grid)
`space.1 = 4`, `space.2 = 8`, `space.3 = 12`, `space.4 = 16`, `space.5 = 20`, `space.6 = 24`, `space.8 = 32`

### Typography (SF Pro, dynamic weights)
| Role | Style |
|---|---|
| Display (cinematic title) | 34 / bold / tracking −0.4 |
| Title (track) | 15 / semibold |
| Subtitle (artist) | 13 / regular / secondary |
| Caption (time, labels) | 11 / medium / monospaced digits / tertiary |
| Lyric active | 28–56 user-adjustable / bold |
| Lyric inactive | same size × 0.92, 35 % opacity, blurred 0.5–1.5 pt with distance |

### Elevation
- **Floating surfaces:** shadow `black 22 %`, radius 24, y 10, plus a 0.5 pt inner hairline (`white 18 %` dark / `black 8 %` light).
- **Artwork:** shadow tinted with `palette.primary` at 35 %, radius 30, y 14.

### Motion
| Token | Curve | Use |
|---|---|---|
| `motion.snappy` | spring(response 0.28, damping 0.86) | buttons, toggles |
| `motion.smooth` | spring(response 0.45, damping 0.9) | expand/collapse, layout |
| `motion.artwork` | 0.6 s crossfade + 0.96→1 scale | track change |
| `motion.palette` | 1.2 s linear interpolation in sRGB | glow and background colour change |
| `motion.lyric` | spring(response 0.5, damping 0.85) | line advance |

Reduced Motion: crossfades replace scale and translation, and glow movement presets fall back to Ambient.

## Surfaces

`Surface` is the single API feature code uses:

- `.glass` — macOS 26+: Liquid Glass (`glassEffect`). macOS 14–15: `NSVisualEffectView(.hudWindow, .behindWindow)` plus a hairline.
- `.material` — standard system material (Apple Minimal).
- `.tinted(palette)` — dark base plus a blurred artwork wash (Cinematic).
- `.custom(color, opacity, blur)` — user-defined.

## Themes

| Theme | Surface | Background | Accent | Text |
|---|---|---|---|---|
| **Apple Minimal** | `.material` | system window | system accent | primary/secondary label |
| **Liquid Glass** | `.glass` | desktop shows through | palette.primary (vivid) | vibrant labels |
| **Cinematic** | `.tinted` | near-black + artwork blur + grain | palette.primary | white / 70 % / 45 % |
| **Custom** | `.custom` | user colour + opacity + blur | user accent | auto contrast from background luminance |

Every theme has a light and a dark variant, except Cinematic, which is always dark.

## Components

- **ArtworkView:** handles the placeholder (SF Symbol `music.note` on a palette wash), crossfades on track change, and draws a tinted shadow.
- **TransportControls:** backward, play/pause, forward (`backward.fill`, `play.fill`/`pause.fill`, `forward.fill`). Hit targets are at least 28 pt. Each button is disabled, with a tooltip, when the source can't perform the command.
- **ProgressScrubber:** shows the interpolated position. Dragging seeks, and it is hidden when the duration is unknown.
- **VolumeSlider:** only rendered when the source reports a volume.
- **SourceBadge:** source icon and name, showing a warning state when permission is missing.
- **GlowPreview:** a miniature live rendering of the edge glow inside Settings.

## Copy

- **Permission prompts** explain the benefit first and the scope second. For example: "Sleeve listens to the sound your Mac plays, only to animate the glow. Audio is analysed in memory and never recorded or uploaded."
- **Empty states** say what to do. For example: "Play something in Spotify or Music."
