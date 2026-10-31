import AfterglowCore
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var settings = env.settings
        let login = env.launchAtLogin
        let lyrics = $settings.settings.lyrics

        ZStack {
            AmbientBackdrop(artwork: nil, palette: env.nowPlaying.palette, intensity: 0.35)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    Text("Settings").font(DS.Font.display)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s4, alignment: .top), GridItem(.flexible(), spacing: DS.Space.s4, alignment: .top)], spacing: DS.Space.s4) {
                        GlassCard(title: "General", symbol: "gearshape") {
                            Toggle("Open at login", isOn: Binding(get: { login.isEnabled }, set: { login.set($0) }))
                                .disabled(!login.isAvailable)
                            if !login.isAvailable {
                                Text("Available when running the installed Afterglow.app.").font(.system(size: 11)).foregroundStyle(.tertiary)
                            } else if login.requiresApproval {
                                HStack {
                                    Text("Approve Afterglow in Login Items to finish.").font(.system(size: 11))
                                    Button("Open Login Items") { login.openSystemSettings() }.controlSize(.small)
                                }
                            }
                            if let error = login.lastError {
                                Text(error).font(.system(size: 11)).foregroundStyle(.red)
                            }
                            Toggle("Detect playing music automatically", isOn: $settings.settings.general.autoDetectMusic)
                            Toggle("Show in menu bar", isOn: $settings.settings.general.showMenuBarIcon)
                        }

                        GlassCard(title: "Lyrics", symbol: "quote.bubble") {
                            Toggle("Show synced lyrics", isOn: lyrics.isEnabled)
                            LabeledPicker(title: "Style", selection: lyrics.style, options: LyricsDisplayStyle.allCases) { $0.displayName }
                            ValueSlider(title: "Text size", value: lyrics.fontSize, range: 20...64, format: { "\(Int($0)) pt" })
                            ValueSlider(title: "Timing for all songs", value: lyrics.globalOffset, range: -2...2, format: { String(format: "%+.1f s", $0) })
                            if #available(macOS 15, *) {
                                Toggle("Translate lyrics", isOn: lyrics.translationEnabled)
                                LabeledPicker(title: "Translate into", selection: Binding(
                                    get: { TranslationLanguage(code: lyrics.wrappedValue.translationTarget) },
                                    set: { lyrics.wrappedValue.translationTarget = $0.code }
                                ), options: TranslationLanguage.all) { $0.name }
                                    .disabled(!lyrics.wrappedValue.translationEnabled)
                                Text("Translation runs on your Mac. macOS may ask to download a language the first time.")
                                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                            }
                        }

                        GlassCard(title: "Privacy", symbol: "hand.raised",
                                  caption: "Afterglow has no accounts, analytics or tracking. Lyrics are fetched from LRCLIB using only the song's title, artist, album and length.") {
                            PrivacyRow(title: "Control Spotify and Music", detail: "Reads what's playing and powers the playback buttons.", action: SystemSettingsLinks.openAutomation)
                            PrivacyRow(title: "System audio", detail: "Animates the edge glow. Analysed in memory, never recorded or uploaded.", action: SystemSettingsLinks.openAudioCapture)
                        }

                        GlassCard(title: "About", symbol: "info.circle") {
                            HStack(spacing: DS.Space.s3) {
                                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Afterglow").font(.system(size: 14, weight: .semibold))
                                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(40)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { login.refresh() }
    }
}

private struct PrivacyRow: View {
    var title: String
    var detail: String
    var action: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open…", action: action).controlSize(.small)
        }
    }
}

struct TranslationLanguage: Hashable, Identifiable {
    var code: String
    var id: String { code }
    var name: String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    static let all = ["en", "es", "fr", "de", "it", "pt", "ja", "ko", "zh-Hans", "zh-Hant", "ar", "hi", "ru", "tr", "nl", "pl", "uk", "vi", "id", "th"]
        .map(TranslationLanguage.init(code:))
}
