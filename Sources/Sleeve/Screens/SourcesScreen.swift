import AfterglowCore
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Music Sources").font(DS.Font.display)
                        Text("When several players are playing, the one highest in this list wins.")
                            .font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
                    }
                    ForEach(Array(priority.enumerated()), id: \.element) { index, source in
                        SourceCard(source: source, rank: index, count: priority.count)
                    }
                    GlassCard(title: "Other apps", symbol: "globe",
                              caption: "Browsers and video players don't share track details with other apps on macOS, so they can't appear in Now Playing. The edge glow still reacts to their sound.") {
                        EmptyView()
                    }
                }
                .padding(40)
                .frame(maxWidth: 820, alignment: .leading)
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
            AppIcon(bundleIdentifier: source.bundleIdentifier, size: 52)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack {
                    Text(source.displayName).font(.system(size: 17, weight: .semibold))
                    badge(status: status, enabled: enabled)
                }
                Text(description(status: status, enabled: enabled))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DS.Space.s2) {
                    if case .limited(.automationDenied) = status {
                        Button("Open Automation Settings", action: SystemSettingsLinks.openAutomation)
                        Button("Check Again") { Task { await provider?.retryPermissions() } }
                    } else if case .limited = status {
                        Button("Retry") { Task { await provider?.retryPermissions() } }
                    }
                    if status == .notRunning, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) {
                        Button("Open \(source.displayName)") {
                            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                        }
                    }
                }
                .controlSize(.small)
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
            }
        }
        .padding(DS.Space.s5)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
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
            case .connected: ("Connected", .green)
            case .limited: ("Needs attention", .orange)
            }
        }
        return StatusPill(text: text, symbol: "circle.fill", color: color)
    }

    private func description(status: ProviderStatus, enabled: Bool) -> String {
        if !enabled { return "Afterglow ignores \(source.displayName) while this is off." }
        switch status {
        case .notInstalled: return "\(source.displayName) isn't installed on this Mac."
        case .notRunning: return "Afterglow connects automatically when \(source.displayName) opens. It never launches it for you."
        case .connected: return "Track details, artwork and playback controls are available."
        case .limited(let error): return error.userMessage
        }
    }
}
