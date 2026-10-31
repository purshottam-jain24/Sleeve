import AfterglowCore
import SwiftUI

struct LyricsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingSearch = false

    var body: some View {
        let nowPlaying = env.nowPlaying
        let settings = env.settings.settings.lyrics
        ZStack {
            AmbientBackdrop(artwork: nowPlaying.artwork, palette: nowPlaying.palette, identity: nowPlaying.snapshot?.track?.cacheKey, intensity: 0.85)

            if !settings.isEnabled {
                LyricsMessage(symbol: "quote.bubble", title: "Lyrics are off", detail: "Turn them on to see synced lyrics for every song.") {
                    Button("Turn On Lyrics") { env.settings.settings.lyrics.isEnabled = true }
                }
            } else if nowPlaying.snapshot?.track == nil {
                NothingPlayingView()
            } else {
                VStack(spacing: 0) {
                    LyricsToolbar(showingSearch: $showingSearch)
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                    LyricsPanel(fontSize: settings.fontSize, compact: false)
                        .padding(.horizontal, settings.style == .glow ? 40 : 96)
                        .frame(maxWidth: 1100)
                    if let attribution {
                        Text(attribution)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.bottom, 12)
                    }
                }
            }
        }
        .playbackKeyboardShortcuts()
    }

    private var attribution: String? {
        env.lyrics.document.map { "Lyrics from \($0.sourceName)" }
    }
}

private struct LyricsToolbar: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var showingSearch: Bool

    var body: some View {
        @Bindable var settings = env.settings
        let nowPlaying = env.nowPlaying
        let track = nowPlaying.snapshot?.track
        HStack(spacing: DS.Space.s3) {
            if let track {
                ArtworkView(image: nowPlaying.artwork, palette: nowPlaying.palette, cornerRadius: DS.Radius.xs, identity: track.cacheKey)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(track.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s4)

            Picker("Style", selection: $settings.settings.lyrics.style) {
                ForEach(LyricsDisplayStyle.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 230)
            .help(settings.settings.lyrics.style.summary)

            OffsetControl()

            if #available(macOS 15, *) {
                Toggle(isOn: $settings.settings.lyrics.translationEnabled) {
                    Image(systemName: "translate")
                }
                .toggleStyle(.button)
                .help("Translate lyrics on-device")
                .accessibilityLabel("Translate lyrics")
            }

            Button { showingSearch.toggle() } label: { Image(systemName: "magnifyingglass") }
                .help("Search for different lyrics")
                .accessibilityLabel("Search lyrics")
                .popover(isPresented: $showingSearch, arrowEdge: .bottom) {
                    LyricsSearch(initialQuery: track.map { "\($0.artist) \($0.title)" } ?? "")
                }
        }
        .controlSize(.regular)
    }
}

/// Nudges lyric timing for the current song in 0.1 s steps (remembered per song).
private struct OffsetControl: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let key = env.nowPlaying.snapshot?.track?.cacheKey
        let value = key.flatMap { env.settings.settings.lyrics.trackOffsets[$0] } ?? 0
        HStack(spacing: 2) {
            Button { adjust(-0.1) } label: { Image(systemName: "minus") }
                .accessibilityLabel("Lyrics earlier")
            Text(String(format: "%+.1fs", value))
                .font(DS.Font.caption)
                .frame(width: 44)
                .contentTransition(.numericText())
                .onTapGesture(count: 2) { set(0) }
                .help("Lyrics timing for this song. Double-click to reset.")
            Button { adjust(0.1) } label: { Image(systemName: "plus") }
                .accessibilityLabel("Lyrics later")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.white.opacity(0.08), in: .capsule)
        .disabled(key == nil)
    }

    private func adjust(_ delta: Double) {
        guard let key = env.nowPlaying.snapshot?.track?.cacheKey else { return }
        let current = env.settings.settings.lyrics.trackOffsets[key] ?? 0
        set(((current + delta) * 10).rounded() / 10)
    }

    private func set(_ value: Double) {
        guard let key = env.nowPlaying.snapshot?.track?.cacheKey else { return }
        var offsets = env.settings.settings.lyrics.trackOffsets
        offsets[key] = abs(value) < 0.05 ? nil : value
        // Keep the map bounded.
        if offsets.count > 500, let first = offsets.keys.first(where: { $0 != key }) { offsets.removeValue(forKey: first) }
        env.settings.settings.lyrics.trackOffsets = offsets
    }
}

private struct LyricsSearch: View {
    @Environment(AppEnvironment.self) private var env
    @State var initialQuery: String
    @State private var query = ""

    var body: some View {
        let lyrics = env.lyrics
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text("Find Lyrics").font(.headline)
            HStack {
                TextField("Artist and song", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await lyrics.search(query) } }
                if lyrics.isSearching { ProgressView().controlSize(.small) }
            }
            if let error = lyrics.searchError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            if !lyrics.candidates.isEmpty {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(lyrics.candidates) { candidate in
                            Button { lyrics.choose(candidate) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(candidate.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                        Text([candidate.artist, candidate.album].filter { !$0.isEmpty }.joined(separator: " — "))
                                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if let d = candidate.duration {
                                        Text(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)).font(DS.Font.caption).foregroundStyle(.tertiary)
                                    }
                                    Text(candidate.hasSynced ? "Synced" : "Plain")
                                        .font(.system(size: 10, weight: .medium))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(candidate.hasSynced ? Color.green.opacity(0.2) : Color.secondary.opacity(0.2), in: .capsule)
                                }
                                .padding(8)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
            Text("Lyrics from \(lyrics.providerName). Your choice is remembered for this song.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(DS.Space.s4)
        .frame(width: 420)
        .onAppear { if query.isEmpty { query = initialQuery } }
    }
}
