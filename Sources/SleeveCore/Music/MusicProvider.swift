import AppKit
import Foundation

public enum ProviderStatus: Sendable, Equatable {
    case notInstalled
    case notRunning
    case connected
    case limited(MusicSourceError)
}

/// A source of now-playing information and playback control.
///
/// Providers are injected into `MusicSourceManager`, so new players (or test doubles)
/// can be added without touching the UI.
@MainActor
public protocol MusicProvider: AnyObject {
    var source: MusicSourceID { get }
    var status: ProviderStatus { get }
    /// Latest known snapshot, or `nil` when the player is not running.
    var snapshot: PlaybackSnapshot? { get }
    /// Invoked whenever `snapshot` or `status` changes.
    var onChange: (@MainActor () -> Void)? { get set }

    func start()
    func stop()
    /// Re-query the player. Cheap enough to call every few seconds while playing.
    func refresh() async
    func perform(_ command: PlaybackCommand) async throws(MusicSourceError)
    func artworkData(for track: Track) async -> Data?
    /// Clears a sticky permission error and tries again.
    func retryPermissions() async
    /// Brings the playing app (and tab, for browsers) to the front.
    func revealPlayer()
}

/// Shared plumbing for players that post distributed notifications and accept Apple Events.
@MainActor
public class ScriptablePlayerProvider: MusicProvider {
    public let source: MusicSourceID
    public private(set) var status: ProviderStatus
    public private(set) var snapshot: PlaybackSnapshot?
    public var onChange: (@MainActor () -> Void)?

    let runner = AppleScriptRunner.shared
    private let notificationName: Notification.Name
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    /// After Automation is denied we stop issuing Apple Events until the user retries,
    /// so we never spam the system with failing requests.
    private var automationBlocked = false

    init(source: MusicSourceID, notificationName: String) {
        self.source = source
        self.notificationName = Notification.Name(notificationName)
        self.status = .notRunning
        updateRunningStatus()
    }

    // MARK: Subclass hooks

    /// Build a snapshot from a distributed-notification payload. No permission needed.
    func snapshot(fromNotification info: [AnyHashable: Any]) -> PlaybackSnapshot? { nil }
    /// AppleScript that returns the player's full state.
    func fetchStateViaScript() async throws(MusicSourceError) -> PlaybackSnapshot { throw .notRunning }
    func commandScript(_ command: PlaybackCommand) -> String { "" }
    public func artworkData(for track: Track) async -> Data? { nil }

    // MARK: Lifecycle

    public var isInstalled: Bool {
        source.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) } != nil
    }

    public var isRunning: Bool {
        source.bundleIdentifier.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false
    }

    public func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: notificationName, object: nil, queue: .main) { [weak self] note in
            // Delivered on the main queue; property-list payloads are immutable.
            nonisolated(unsafe) let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { self?.handleNotification(info) }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                MainActor.assumeIsolated { self?.handleWorkspaceChange(bundleID: bundleID) }
            })
        }
        Task { await refresh() }
    }

    public func stop() {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        workspaceObservers.removeAll()
    }

    public func refresh() async {
        guard isRunning else {
            apply(snapshot: nil, status: isInstalled ? .notRunning : .notInstalled)
            return
        }
        guard !automationBlocked else { return }
        do {
            let fresh = try await fetchStateViaScript()
            // The app may have quit while the script was in flight.
            guard isRunning else { return }
            apply(snapshot: fresh, status: .connected)
        } catch {
            handle(error)
        }
    }

    public func perform(_ command: PlaybackCommand) async throws(MusicSourceError) {
        guard isRunning else { throw .notRunning }
        if automationBlocked { throw .automationDenied }
        do {
            _ = try await runner.run(commandScript(command), cache: command.isParameterless) { _ in () }
        } catch {
            handle(error)
            throw error
        }
        await refresh()
    }

    public func retryPermissions() async {
        automationBlocked = false
        await refresh()
    }

    public func revealPlayer() {
        guard let id = source.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Internals

    private func handleNotification(_ info: [AnyHashable: Any]) {
        if let quick = snapshot(fromNotification: info) {
            // Keep enrichment we cannot get from the notification (artwork URL, volume, position).
            var merged = quick
            if let previous = snapshot, previous.track?.cacheKey == quick.track?.cacheKey {
                let artworkURL = merged.track?.artworkURL ?? previous.track?.artworkURL
                merged.track?.artworkURL = artworkURL
                merged.volume = merged.volume ?? previous.volume
                if merged.position == nil, let p = previous.position(at: Date()) {
                    merged.position = p
                }
            }
            let currentStatus: ProviderStatus = automationBlocked ? .limited(.automationDenied) : .connected
            apply(snapshot: merged, status: currentStatus)
        }
        Task { await refresh() }
    }

    private func handleWorkspaceChange(bundleID: String?) {
        guard bundleID == source.bundleIdentifier else { return }
        updateRunningStatus()
        if !isRunning {
            apply(snapshot: nil, status: .notRunning)
        } else {
            Task { await refresh() }
        }
    }

    private func updateRunningStatus() {
        if !isInstalled {
            status = .notInstalled
        } else if !isRunning {
            status = .notRunning
        }
    }

    private func handle(_ error: MusicSourceError) {
        switch error {
        case .automationDenied:
            automationBlocked = true
            apply(snapshot: snapshot, status: .limited(.automationDenied))
        case .notRunning:
            apply(snapshot: nil, status: .notRunning)
        default:
            Log.music.error("\(self.source.rawValue, privacy: .public) script error: \(error.userMessage, privacy: .public)")
            apply(snapshot: snapshot, status: .limited(error))
        }
    }

    private func apply(snapshot newSnapshot: PlaybackSnapshot?, status newStatus: ProviderStatus) {
        guard newSnapshot != snapshot || newStatus != status else { return }
        snapshot = newSnapshot
        status = newStatus
        onChange?()
    }
}

extension PlaybackCommand {
    var isParameterless: Bool {
        switch self {
        case .playPause, .next, .previous: true
        case .seek, .setVolume: false
        }
    }
}

extension PlaybackState {
    /// Parses "Playing" / "playing" / "fast forwarding" etc.
    init(playerState: String?) {
        switch playerState?.lowercased() {
        case "playing", "fast forwarding", "rewinding": self = .playing
        case "paused": self = .paused
        default: self = .stopped
        }
    }
}

func formatNumber(_ value: Double) -> String {
    String(format: "%.3f", value)
}
