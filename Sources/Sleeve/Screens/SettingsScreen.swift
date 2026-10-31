import SleeveCore
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var settings = env.settings
        let login = env.launchAtLogin
        let lyrics = $settings.settings.lyrics

        ZStack {
            AmbientBackdrop(artwork: nil, palette: env.nowPlaying.palette, intensity: 0.3)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    PageHeader(title: "Settings", subtitle: "How Sleeve starts, shows lyrics and uses your Mac.")

                    MasonryLayout {
                        GlassCard(title: "General", symbol: "switch.2") {
                            SettingToggle(title: "Open at login", detail: loginDetail(login),
                                          isOn: Binding(get: { login.isEnabled }, set: { login.set($0) }))
                                .disabled(!login.isAvailable)
                            if login.isAvailable, login.requiresApproval {
                                Button("Open Login Items") { login.openSystemSettings() }.buttonStyle(.quiet)
                            }
                            if let error = login.lastError {
                                Text(error).font(.system(size: 11)).foregroundStyle(.red)
                            }
                            RowDivider()
                            SettingToggle(title: "Detect playing music", detail: "Follow Spotify, Music and browsers automatically.",
                                          isOn: $settings.settings.general.autoDetectMusic)
                            RowDivider()
                            SettingToggle(title: "Show in menu bar", detail: "Quick controls for music, glow and wallpaper.",
                                          isOn: $settings.settings.general.showMenuBarIcon)
                        }

                        GlassCard(title: "Lyrics", symbol: "quote.bubble") {
                            SettingToggle(title: "Show synced lyrics", detail: nil, isOn: lyrics.isEnabled)
                            RowDivider()
                            LabeledPicker(title: "Style", selection: lyrics.style, options: LyricsDisplayStyle.allCases) { $0.displayName }
                            RowDivider()
                            ValueSlider(title: "Text size", value: lyrics.fontSize, range: 20...64, format: { "\(Int($0)) pt" })
                            ValueSlider(title: "Timing for all songs", value: lyrics.globalOffset, range: -2...2, format: { String(format: "%+.1f s", $0) })
                            if #available(macOS 15, *) {
                                RowDivider()
                                SettingToggle(title: "Translate lyrics", detail: "Runs on your Mac. macOS may download the language the first time.",
                                              isOn: lyrics.translationEnabled)
                                LabeledPicker(title: "Translate into", selection: Binding(
                                    get: { TranslationLanguage(code: lyrics.wrappedValue.translationTarget) },
                                    set: { lyrics.wrappedValue.translationTarget = $0.code }
                                ), options: TranslationLanguage.all) { $0.name }
                                    .disabled(!lyrics.wrappedValue.translationEnabled)
                            }
                        }

                        GlassCard(title: "Privacy", symbol: "hand.raised",
                                  caption: "No accounts, analytics or tracking. Lyrics are fetched from LRCLIB using only the song's title, artist, album and length.") {
                            PrivacyRow(title: "Control music apps", detail: "Reads what's playing and powers the playback buttons.", action: SystemSettingsLinks.openAutomation)
                            RowDivider()
                            PrivacyRow(title: "System audio", detail: "Only with Edge Glow › Follow the beat. Analysed in memory, never recorded or uploaded.", action: SystemSettingsLinks.openAudioCapture)
                        }

                        AboutCard()
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 36)
                .frame(maxWidth: 1040, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { login.refresh() }
    }

    private func loginDetail(_ login: LaunchAtLogin) -> String? {
        if !login.isAvailable { return "Available when running the installed Sleeve.app." }
        if login.requiresApproval { return "Approve Sleeve in Login Items to finish." }
        return nil
    }
}

private struct AboutCard: View {
    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        HStack(spacing: DS.Space.s4) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text("Sleeve")
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text("Version \(version)")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                Text("Lyrics, edge glow and wallpaper for the music you play.")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct PrivacyRow: View {
    var title: String
    var detail: String
    var action: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.Font.title).foregroundStyle(DS.Palette.textPrimary)
                Text(detail).font(.system(size: 11)).foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Space.s3)
            Button("Open", action: action).buttonStyle(.quiet)
                .help("Opens this permission in System Settings")
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
