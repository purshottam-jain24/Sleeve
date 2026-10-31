import SleeveCore
import AppKit
import SwiftUI

struct SourcesScreen: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let priority = env.settings.settings.sources.priority
        ZStack {
            AmbientBackdrop(artwork: nil, palette: env.nowPlaying.palette, intensity: 0.35)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    PageHeader(title: "Music Sources", subtitle: "When several players are playing, the one highest in this list wins.")
                    VStack(spacing: DS.Space.s4) {
                        ForEach(Array(priority.enumerated()), id: \.element) { index, source in
                            SourceCard(source: source, rank: index, count: priority.count)
                        }
                    }
                    Text("Other apps, like video players, don't share what they're playing, so they can't appear in Now Playing. The edge glow still reacts to their sound.")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 36)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct SourceCard: View {
    @Environment(AppEnvironment.self) private var env
    var source: MusicSourceID
    var rank: Int
    var count: Int

    var body: some View {
        _ = env.sources.statusRevision
        let provider = env.sources.provider(for: source)
        let status = provider?.status ?? .notInstalled
        let enabled = env.settings.settings.sources.enabled.contains(source)

        return HStack(alignment: .top, spacing: DS.Space.s4) {
            AppIcon(bundleIdentifier: source.bundleIdentifier, size: 40)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s3) {
                    Text(source.displayName).font(.system(size: 14, weight: .semibold)).foregroundStyle(DS.Palette.textPrimary)
                    badge(status: status, enabled: enabled)
                }
                Text(description(status: status, enabled: enabled))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DS.Space.s2) {
                    if case .limited(.automationDenied) = status {
                        Button("Open Automation Settings", action: SystemSettingsLinks.openAutomation)
                        Button("Check Again") { Task { await provider?.retryPermissions() } }
                    } else if case .limited(.browserScriptingOff) = status {
                        // Basic details work; full details are optional, not an error.
                    } else if case .limited = status {
                        Button("Retry") { Task { await provider?.retryPermissions() } }
                    }
                    if status == .notRunning, let bundleID = source.bundleIdentifier,
                       let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                        Button("Open \(source.displayName)") {
                            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                        }
                    }
                }
                .buttonStyle(.quiet)
                if source == .web, let browsers = provider as? BrowserMediaService {
                    WebBrowsersDetail(service: browsers)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: DS.Space.s3) {
                Toggle("Enabled", isOn: Binding(
                    get: { enabled },
                    set: { on in
                        if on { env.settings.settings.sources.enabled.insert(source) }
                        else { env.settings.settings.sources.enabled.remove(source) }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel("Use \(source.displayName)")
                HStack(spacing: 2) {
                    Button { move(by: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(rank == 0)
                        .accessibilityLabel("Higher priority")
                    Button { move(by: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(rank == count - 1)
                        .accessibilityLabel("Lower priority")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(DS.Palette.textTertiary)
            }
        }
        .padding(DS.Space.s5)
        .cardSurface()
    }

    private func move(by offset: Int) {
        var list = env.settings.settings.sources.priority
        let target = rank + offset
        guard list.indices.contains(target) else { return }
        withAnimation(DS.Motion.smooth) {
            list.swapAt(rank, target)
            env.settings.settings.sources.priority = list
        }
    }

    private func badge(status: ProviderStatus, enabled: Bool) -> some View {
        let (text, color): (String, Color) = if !enabled { ("Off", .secondary) } else {
            switch status {
            case .notInstalled: ("Not installed", .secondary)
            case .notRunning: ("Not running", .secondary)
            case .connected, .limited(.browserScriptingOff): ("Connected", .green)
            case .limited: ("Needs attention", .orange)
            }
        }
        return StatusPill(text: text, symbol: "circle.fill", color: color)
    }

    private func description(status: ProviderStatus, enabled: Bool) -> String {
        if !enabled { return "Sleeve ignores \(source.displayName) while this is off." }
        if source == .web {
            switch status {
            case .notInstalled: return "No supported browser found. Safari, Chrome, Arc, Brave, Edge and Vivaldi are supported; Firefox can't share tab details."
            case .limited(.automationDenied): return MusicSourceError.automationDenied.userMessage
            case .limited(.browserScriptingOff(let browser)):
                return "Showing title and cover art from \(browser). Get full details for the artist, song length, timeline and playback controls."
            default: return "YouTube, YouTube Music, SoundCloud and more, with cover art. Checked only while a browser is playing sound."
            }
        }
        switch status {
        case .notInstalled: return "\(source.displayName) isn't installed on this Mac."
        case .notRunning: return "Sleeve connects automatically when \(source.displayName) opens. It never launches it for you."
        case .connected: return "Track details, artwork and playback controls are available."
        case .limited(let error): return error.userMessage
        }
    }
}

/// Per-browser status for the Web source, with the one setting that unlocks full details.
private struct WebBrowsersDetail: View {
    @Environment(AppEnvironment.self) private var env
    var service: BrowserMediaService

    var body: some View {
        _ = env.sources.statusRevision
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(service.installedBrowsers) { browser in
                let basic = service.javaScriptOff.contains(browser.bundleID)
                HStack(spacing: 8) {
                    AppIcon(bundleIdentifier: browser.bundleID, size: 16)
                    Text(browser.name).font(.system(size: 12, weight: .medium)).foregroundStyle(DS.Palette.textPrimary)
                    Spacer()
                    if basic {
                        FullDetailsButton(browser: browser) { Task { await service.retryPermissions() } }
                    } else {
                        Text("Full details")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Palette.textTertiary)
                            .help("Artist, song length, timeline and playback controls.")
                    }
                }
                .padding(.vertical, 7)
                if browser != service.installedBrowsers.last { RowDivider() }
            }
        }
        .padding(.horizontal, DS.Space.s3)
        .background(DS.Palette.inset, in: .rect(cornerRadius: DS.Radius.md, style: .continuous))
        .padding(.top, 4)
    }
}

/// "Get full details" with the browser's one-time setting, and a re-check once it's on.
private struct FullDetailsButton: View {
    var browser: Browser
    var recheck: () -> Void
    @State private var showing = false

    var body: some View {
        Button("Get full details…") { showing = true }
            .buttonStyle(.quiet)
            .popover(isPresented: $showing, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    Text("Full details from \(browser.name)").font(.system(size: 13, weight: .semibold))
                    Text("\(browser.name) shows Sleeve only the tab title until you allow it to read what's playing. It's a one-time setting:")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(browser.javaScriptSettingHint)
                        .font(.system(size: 12, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("You then get the artist, song length, a timeline on the screensaver, and play, pause, skip and seek.")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("I've Turned It On") {
                            showing = false
                            recheck()
                        }
                        .buttonStyle(.quiet)
                    }
                }
                .padding(DS.Space.s4)
                .frame(width: 320)
            }
    }
}
