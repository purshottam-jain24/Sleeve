import Foundation

public enum MusicSourceError: Error, Sendable, Equatable {
    case notRunning
    /// The user denied (or has not yet granted) Automation permission for this player.
    case automationDenied
    case timedOut
    case scriptFailed(code: Int, message: String)

    public var userMessage: String {
        switch self {
        case .notRunning: "The player is not running."
        case .automationDenied: "Afterglow isn't allowed to control this player. Allow it in System Settings › Privacy & Security › Automation."
        case .timedOut: "The player did not respond in time."
        case .scriptFailed(_, let message): message
        }
    }
}

/// Runs AppleScript off the main thread on one serial queue.
///
/// `NSAppleScript` is not thread-safe, so every instance is created and executed on
/// `queue` only. Results are parsed on the same queue into `Sendable` values.
final class AppleScriptRunner: @unchecked Sendable {
    static let shared = AppleScriptRunner()

    private let queue = DispatchQueue(label: "app.afterglow.applescript", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:]

    /// - Parameter cache: keep the compiled script for reuse. Use `false` for scripts
    ///   with interpolated values (seek/volume) so the cache does not grow unbounded.
    func run<T: Sendable>(
        _ source: String,
        cache: Bool = true,
        parse: @escaping @Sendable (NSAppleEventDescriptor) -> T
    ) async throws(MusicSourceError) -> T {
        let result: Result<T, MusicSourceError> = await withCheckedContinuation { continuation in
            queue.async {
                let script: NSAppleScript
                if let existing = self.compiled[source] {
                    script = existing
                } else if let created = NSAppleScript(source: source) {
                    script = created
                    if cache { self.compiled[source] = created }
                } else {
                    continuation.resume(returning: .failure(.scriptFailed(code: 0, message: "Invalid script")))
                    return
                }
                var errorInfo: NSDictionary?
                let descriptor = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    continuation.resume(returning: .failure(Self.map(errorInfo)))
                } else {
                    continuation.resume(returning: .success(parse(descriptor)))
                }
            }
        }
        return try result.get()
    }

    private static func map(_ info: NSDictionary) -> MusicSourceError {
        let code = (info[NSAppleScript.errorNumber] as? Int) ?? 0
        let message = (info[NSAppleScript.errorMessage] as? String) ?? "AppleScript error \(code)"
        switch code {
        case -1743, -10004: return .automationDenied
        case -600: return .notRunning
        case -1712: return .timedOut
        default: return .scriptFailed(code: code, message: message)
        }
    }
}

extension NSAppleEventDescriptor {
    /// 1-based list access that tolerates out-of-range indices.
    func item(_ index: Int) -> NSAppleEventDescriptor? {
        guard index >= 1, index <= numberOfItems else { return nil }
        return atIndex(index)
    }

    var nonEmptyString: String? {
        guard let value = stringValue, !value.isEmpty else { return nil }
        return value
    }
}
