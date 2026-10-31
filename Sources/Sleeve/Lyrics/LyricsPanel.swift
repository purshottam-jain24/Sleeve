import AfterglowCore
import SwiftUI
@preconcurrency import Translation

/// Lyrics for the current track in whatever state they're in: loading, synced, plain,
/// instrumental or missing. Never shows invented text.
struct LyricsPanel: View {
    @Environment(AppEnvironment.self) private var env
    var fontSize: CGFloat
    var compact: Bool
    @State private var translations: [Int: String] = [:]
    @State private var translationUnavailable = false

    var body: some View {
        let lyrics = env.lyrics
        let settings = env.settings.settings.lyrics
        Group {
            switch lyrics.state {
            case .idle:
                Color.clear
            case .loading:
                LyricsMessage(symbol: nil, title: "Finding lyrics…", detail: nil) {
                    ProgressView().controlSize(.small)
                }
            case .loaded(let document):
                if document.isSynced {
                    LyricsView(
                        document: document,
                        style: compact ? .focus : settings.style,
                        fontSize: fontSize,
                        palette: env.nowPlaying.palette,
                        translations: settings.translationEnabled ? translations : [:],
                        duration: env.nowPlaying.snapshot?.track?.duration,
                        isPlaying: env.nowPlaying.isPlaying,
                        position: { env.lyricsPosition(at: $0) },
                        onSeek: { time in
                            let offset = settings.offset(for: env.nowPlaying.snapshot?.track)
                            env.nowPlaying.perform(.seek(max(0, time - offset)))
                        }
                    )
                } else {
                    PlainLyricsView(lines: document.plain, fontSize: fontSize * 0.7, translations: settings.translationEnabled ? translations : [:])
                }
            case .instrumental:
                LyricsMessage(symbol: "music.note", title: "Instrumental", detail: "Nothing to sing along to. Enjoy the music.") { EmptyView() }
            case .notFound:
                LyricsMessage(symbol: "text.page.slash", title: "No lyrics found", detail: "\(lyrics.providerName) doesn't have lyrics for this song yet.") {
                    actions
                }
            case .failed(let message):
                LyricsMessage(symbol: "wifi.exclamationmark", title: "Lyrics unavailable", detail: message) {
                    actions
                }
            }
        }
        .modifier(LyricsTranslation(
            document: lyrics.document,
            enabled: settings.translationEnabled,
            target: settings.translationTarget,
            translations: $translations,
            unavailable: $translationUnavailable
        ))
        .overlay(alignment: .bottomTrailing) {
            if settings.translationEnabled, translationUnavailable, lyrics.document != nil {
                StatusPill(text: "Translation unavailable for this language", symbol: "character.bubble")
                    .padding(DS.Space.s3)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: DS.Space.s2) {
            Button("Try Again") { env.lyrics.retry() }
            if compact {
                Button("Search…") { env.section = .lyrics }
            }
        }
        .controlSize(.small)
    }
}

struct LyricsMessage<Accessory: View>: View {
    var symbol: String?
    var title: String
    var detail: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: DS.Space.s3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text(title).font(.system(size: 20, weight: .semibold))
            if let detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            accessory
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Unsynced lyrics: shown as-is, clearly labelled, never auto-scrolled as if timed.
private struct PlainLyricsView: View {
    var lines: [String]
    var fontSize: CGFloat
    var translations: [Int: String]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: fontSize * 0.5) {
                StatusPill(text: "These lyrics aren't time-synced", symbol: "clock.badge.questionmark")
                    .padding(.bottom, DS.Space.s3)
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: fontSize, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        if let translation = translations[index] {
                            Text(translation).font(.system(size: fontSize * 0.6)).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .mask(EdgeFade())
    }
}

struct EdgeFade: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.12),
            .init(color: .black, location: 0.82),
            .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}

/// On-device translation via Apple's Translation framework (macOS 15+).
private struct LyricsTranslation: ViewModifier {
    var document: LyricsDocument?
    var enabled: Bool
    var target: String
    @Binding var translations: [Int: String]
    @Binding var unavailable: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.modifier(TranslationTaskModifier(
                document: document, enabled: enabled, target: target,
                translations: $translations, unavailable: $unavailable
            ))
        } else {
            content
        }
    }
}

@available(macOS 15, *)
private struct TranslationTaskModifier: ViewModifier {
    var document: LyricsDocument?
    var enabled: Bool
    var target: String
    @Binding var translations: [Int: String]
    @Binding var unavailable: Bool
    @State private var configuration: TranslationSession.Configuration?

    private var key: String { "\(document?.sourceID ?? "none")|\(document?.synced.count ?? 0)|\(enabled)|\(target)" }

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                guard let document else { return }
                let lines: [(Int, String)] = document.isSynced
                    ? document.synced.filter { !$0.isGap }.map { ($0.id, $0.text) }
                    : document.plain.enumerated().filter { !$0.element.isEmpty }.map { ($0.offset, $0.element) }
                do {
                    translations = try await Self.translate(lines, using: session)
                    unavailable = false
                } catch {
                    translations = [:]
                    unavailable = true
                }
            }
            .onChange(of: key, initial: true) {
                translations = [:]
                unavailable = false
                configuration = enabled && document != nil
                    ? TranslationSession.Configuration(source: nil, target: Locale.Language(identifier: target))
                    : nil
            }
    }

    /// Runs off the main actor; inputs and outputs are plain Sendable values.
    private nonisolated static func translate(_ lines: [(Int, String)], using session: TranslationSession) async throws -> [Int: String] {
        let requests = lines.map { TranslationSession.Request(sourceText: $0.1, clientIdentifier: String($0.0)) }
        var result: [Int: String] = [:]
        for response in try await session.translations(from: requests) {
            if let id = response.clientIdentifier.flatMap(Int.init), response.targetText != response.sourceText {
                result[id] = response.targetText
            }
        }
        return result
    }
}
