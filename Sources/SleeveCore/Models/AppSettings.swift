import Foundation

// All settings types decode field-by-field with fallbacks so that adding,
// removing or retyping a field never discards the rest of a user's settings.

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var general = GeneralSettings()
    public var sources = SourceSettings()
    public var glow = GlowSettings()
    public var lyrics = LyricsSettings()
    public var wallpaper = WallpaperSettings()

    public init() {}

    enum CodingKeys: String, CodingKey { case general, sources, glow, lyrics, wallpaper }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        general = c.value(.general, default: d.general)
        sources = c.value(.sources, default: d.sources)
        glow = c.value(.glow, default: d.glow)
        lyrics = c.value(.lyrics, default: d.lyrics)
        wallpaper = c.value(.wallpaper, default: d.wallpaper)
    }
}

// MARK: - Wallpaper

/// Live video wallpaper and the lock-screen artwork. Nothing here runs unless the user
/// picks a video or turns the artwork switch on.
public struct WallpaperSettings: Codable, Sendable, Equatable {
    /// The library video playing on the desktop; nil when live wallpaper is off.
    public var activeVideoID: UUID?
    public var allDisplays = true
    /// Pause the video while on battery (saves the most energy).
    public var pauseOnBattery = true
    /// While music plays, show its artwork as the desktop picture, which macOS also uses
    /// on the lock screen. Your own picture comes back when music stops.
    public var artworkOnLockScreen = false

    public init() {}

    enum CodingKeys: String, CodingKey { case activeVideoID, allDisplays, pauseOnBattery, artworkOnLockScreen }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WallpaperSettings()
        activeVideoID = c.value(.activeVideoID, default: d.activeVideoID)
        allDisplays = c.value(.allDisplays, default: d.allDisplays)
        pauseOnBattery = c.value(.pauseOnBattery, default: d.pauseOnBattery)
        artworkOnLockScreen = c.value(.artworkOnLockScreen, default: d.artworkOnLockScreen)
    }
}

// MARK: - General

public struct GeneralSettings: Codable, Sendable, Equatable {
    /// Detect music automatically and react to the playing source.
    public var autoDetectMusic = true
    public var showMenuBarIcon = true

    public init() {}

    enum CodingKeys: String, CodingKey { case autoDetectMusic, showMenuBarIcon }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GeneralSettings()
        autoDetectMusic = c.value(.autoDetectMusic, default: d.autoDetectMusic)
        showMenuBarIcon = c.value(.showMenuBarIcon, default: d.showMenuBarIcon)
    }
}

// MARK: - Sources

public struct SourceSettings: Codable, Sendable, Equatable {
    /// Earlier entries win when several sources are playing at once.
    public var priority: [MusicSourceID] = [.spotify, .appleMusic, .web]
    public var enabled: Set<MusicSourceID> = Set(MusicSourceID.allCases)

    public init() {}

    enum CodingKeys: String, CodingKey { case priority, enabled }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SourceSettings()
        let decoded: [MusicSourceID] = c.value(.priority, default: d.priority)
        // Sources added in newer versions go at the end of the list, switched on.
        let added = MusicSourceID.allCases.filter { !decoded.contains($0) }
        priority = decoded + added
        enabled = c.value(.enabled, default: d.enabled).union(added)
    }

    public func rank(of source: MusicSourceID) -> Int {
        priority.firstIndex(of: source) ?? priority.count
    }
}

// MARK: - Edge Glow

public enum GlowPreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case ambient, musicSync, flow, pulse, spectrum, cinematic, aurora, comet
    case halo, tide, prism, ember, studio

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ambient: "Ambient"
        case .musicSync: "Music Sync"
        case .flow: "Flow"
        case .pulse: "Pulse"
        case .spectrum: "Spectrum"
        case .cinematic: "Cinematic"
        case .aurora: "Aurora"
        case .comet: "Comet"
        case .halo: "Halo"
        case .tide: "Tide"
        case .prism: "Prism"
        case .ember: "Ember"
        case .studio: "Studio"
        }
    }

    public var summary: String {
        switch self {
        case .ambient: "Soft, static ambient light."
        case .musicSync: "Brightness follows the music."
        case .flow: "Colours travel around the display."
        case .pulse: "Gently expands and contracts with the beat."
        case .spectrum: "An equaliser wrapped around your screen: bass below, treble above."
        case .cinematic: "Slow, atmospheric movement in the album's colours."
        case .aurora: "Ribbons of light drift and shimmer with the melody."
        case .comet: "Twin comets race the edge and surge on every beat."
        case .halo: "Light gathers in the corners and blooms with the bass."
        case .tide: "Colour rises up the sides like water as the song swells."
        case .prism: "The palette splits into drifting bands that flare on the highs."
        case .ember: "A low, warm flicker with sparks on the beat."
        case .studio: "Soft neutral light on top, album colour below. Made for video calls."
        }
    }

    /// Whether the preset needs live audio. Ambient and Studio never capture audio.
    public var usesAudio: Bool { self != .ambient && self != .studio }
}

public enum GlowIdleBehavior: String, Codable, Sendable, CaseIterable, Identifiable {
    case breathe, dim, steady, hide
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .breathe: "Breathe slowly"
        case .dim: "Dim"
        case .steady: "Stay lit"
        case .hide: "Turn off"
        }
    }
}

public enum NotchMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case wrap, gap, ignore
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .wrap: "Wrap around notch"
        case .gap: "Leave gap at notch"
        case .ignore: "Straight edge"
        }
    }
}

public enum DisplaySelection: Codable, Sendable, Equatable, Hashable {
    case all
    case main
    /// `CGDirectDisplayID`s. Displays that are not connected are skipped.
    case specific([UInt32])
}

/// The tunable look of the glow. Saved as part of custom presets.
public struct GlowStyle: Codable, Sendable, Equatable {
    public var preset: GlowPreset = .cinematic
    /// 0...1
    public var intensity = 0.8
    /// Width of the bright band in points (2...40).
    public var thickness = 8.0
    /// Reach of the outer glow in points (20...320).
    public var spread = 140.0
    /// Softness multiplier, 0...1.
    public var blur = 0.65
    /// 0.1...3
    public var animationSpeed = 1.0
    /// 0...2
    public var audioSensitivity = 1.0
    /// 0...2
    public var bassSensitivity = 1.0
    /// 0 = very smooth, 1 = very snappy.
    public var responseSpeed = 0.5
    /// Degrees, rotates where the gradient starts.
    public var gradientAngle = 0.0
    public var beatSync = true
    public var useArtworkColors = true
    public var primaryColor = RGBAColor(red: 0.42, green: 0.36, blue: 1.0)
    public var secondaryColor = RGBAColor(red: 1.0, green: 0.36, blue: 0.62)

    public init() {}

    enum CodingKeys: String, CodingKey {
        case preset, intensity, thickness, spread, blur, animationSpeed, audioSensitivity,
             bassSensitivity, responseSpeed, gradientAngle, beatSync, useArtworkColors,
             primaryColor, secondaryColor
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GlowStyle()
        preset = c.value(.preset, default: d.preset)
        intensity = c.value(.intensity, default: d.intensity)
        thickness = c.value(.thickness, default: d.thickness)
        spread = c.value(.spread, default: d.spread)
        blur = c.value(.blur, default: d.blur)
        animationSpeed = c.value(.animationSpeed, default: d.animationSpeed)
        audioSensitivity = c.value(.audioSensitivity, default: d.audioSensitivity)
        bassSensitivity = c.value(.bassSensitivity, default: d.bassSensitivity)
        responseSpeed = c.value(.responseSpeed, default: d.responseSpeed)
        gradientAngle = c.value(.gradientAngle, default: d.gradientAngle)
        beatSync = c.value(.beatSync, default: d.beatSync)
        useArtworkColors = c.value(.useArtworkColors, default: d.useArtworkColors)
        primaryColor = c.value(.primaryColor, default: d.primaryColor)
        secondaryColor = c.value(.secondaryColor, default: d.secondaryColor)
    }
}

public struct CustomGlowPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var style: GlowStyle

    public init(id: UUID = UUID(), name: String, style: GlowStyle) {
        self.id = id
        self.name = name
        self.style = style
    }
}

public struct GlowSettings: Codable, Sendable, Equatable {
    public var isEnabled = false
    public var style = GlowStyle()
    /// Default: no glow while nothing is playing.
    public var idleBehavior: GlowIdleBehavior = .hide
    public var notchMode: NotchMode = .wrap
    /// Corner radius of the glow path; matches built-in display corners by default.
    public var cornerRadius = 10.0
    public var displays: DisplaySelection = .all
    public var customPresets: [CustomGlowPreset] = []
    /// Lets highlights exceed SDR white on XDR/HDR displays (uses more power).
    public var hdrHighlights = false
    /// Sync the glow to the beat by analysing system audio. Off by default: the glow then
    /// moves gently on its own while music plays and audio is never captured.
    public var followBeat = false
    /// With `followBeat`: also react to sound from apps Sleeve can't detect.
    public var reactToAllAudio = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case isEnabled, style, idleBehavior, notchMode, cornerRadius, displays, customPresets, hdrHighlights, followBeat, reactToAllAudio
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GlowSettings()
        isEnabled = c.value(.isEnabled, default: d.isEnabled)
        style = c.value(.style, default: d.style)
        idleBehavior = c.value(.idleBehavior, default: d.idleBehavior)
        notchMode = c.value(.notchMode, default: d.notchMode)
        cornerRadius = c.value(.cornerRadius, default: d.cornerRadius)
        displays = c.value(.displays, default: d.displays)
        customPresets = c.value(.customPresets, default: d.customPresets)
        hdrHighlights = c.value(.hdrHighlights, default: d.hdrHighlights)
        followBeat = c.value(.followBeat, default: d.followBeat)
        reactToAllAudio = c.value(.reactToAllAudio, default: d.reactToAllAudio)
    }
}

// MARK: - Lyrics

public enum LyricsDisplayStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case focus, karaoke, glow
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .focus: "Focus"
        case .karaoke: "Karaoke"
        case .glow: "Glow"
        }
    }
    public var summary: String {
        switch self {
        case .focus: "The sung line is bold and sharp; the rest softly recede."
        case .karaoke: "Colour sweeps through each line as it's sung."
        case .glow: "One luminous line at a time, lit in the album's colours."
        }
    }
}

public struct LyricsSettings: Codable, Sendable, Equatable {
    public var isEnabled = true
    public var style: LyricsDisplayStyle = .focus
    /// Points, for the active line in the full lyrics view.
    public var fontSize = 34.0
    /// Seconds added to playback position for every track.
    public var globalOffset = 0.0
    /// Per-track adjustments keyed by `Track.cacheKey`.
    public var trackOffsets: [String: Double] = [:]
    public var translationEnabled = false
    /// BCP-47 language code, e.g. "en", "es", "ja".
    public var translationTarget = "en"

    public init() {}

    enum CodingKeys: String, CodingKey {
        case isEnabled, style, fontSize, globalOffset, trackOffsets, translationEnabled, translationTarget
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LyricsSettings()
        isEnabled = c.value(.isEnabled, default: d.isEnabled)
        style = c.value(.style, default: d.style)
        fontSize = c.value(.fontSize, default: d.fontSize)
        globalOffset = c.value(.globalOffset, default: d.globalOffset)
        trackOffsets = c.value(.trackOffsets, default: d.trackOffsets)
        translationEnabled = c.value(.translationEnabled, default: d.translationEnabled)
        translationTarget = c.value(.translationTarget, default: d.translationTarget)
    }

    public func offset(for track: Track?) -> Double {
        globalOffset + (track.flatMap { trackOffsets[$0.cacheKey] } ?? 0)
    }
}
