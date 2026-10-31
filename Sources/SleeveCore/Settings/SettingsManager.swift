import Foundation
import Observation

/// Owns the persisted `AppSettings` document.
///
/// Settings are stored as JSON in `~/Library/Application Support/Sleeve/settings.json`.
/// Writes are debounced so dragging a slider does not hammer the disk.
@MainActor
@Observable
public final class SettingsManager {
    public var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            scheduleSave()
        }
    }

    private let fileURL: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// - Parameter fileURL: `nil` keeps settings in memory only (tests, previews).
    public init(fileURL: URL? = SettingsManager.defaultFileURL) {
        self.fileURL = fileURL
        self.settings = Self.load(from: fileURL)
    }

    /// `SLEEVE_SETTINGS_FILE` points the app at another settings file (testing, demos)
    /// without touching the user's own.
    public static var defaultFileURL: URL? {
        if let override = ProcessInfo.processInfo.environment["SLEEVE_SETTINGS_FILE"] {
            return URL(fileURLWithPath: override)
        }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("Sleeve", isDirectory: true).appendingPathComponent("settings.json")
    }

    private static func load(from url: URL?) -> AppSettings {
        guard let url, let data = try? Data(contentsOf: url) else { return AppSettings() }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            Log.settings.error("Settings unreadable, using defaults: \(error.localizedDescription, privacy: .public)")
            return AppSettings()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    public func saveNow() {
        saveTask?.cancel()
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: fileURL, options: .atomic)
        } catch {
            Log.settings.error("Saving settings failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
