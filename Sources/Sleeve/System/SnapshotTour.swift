#if DEBUG
import AppKit

/// Debug-only: when `AFTERGLOW_SNAPSHOT_DIR` is set, visits every section and saves a
/// PNG of the main window. Lets UI be reviewed without Screen Recording permission.
@MainActor
enum SnapshotTour {
    static func runIfRequested(_ env: AppEnvironment) {
        guard let dir = ProcessInfo.processInfo.environment["AFTERGLOW_SNAPSHOT_DIR"] else { return }
        // A locked screen puts the app into App Nap, which stretches the sleeps below.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Snapshot tour")
        Task {
            defer { ProcessInfo.processInfo.endActivity(activity) }
            try? await Task.sleep(for: .seconds(2))
            for section in AppSection.allCases {
                env.section = section
                // Show long screens in full by making the window very tall.
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }) {
                    let height: CGFloat = section == .glow ? 2700 : 800
                    window.setFrame(NSRect(x: window.frame.minX, y: window.frame.maxY - height, width: 1240, height: height), display: true)
                }
                try? await Task.sleep(for: .seconds(2.5))
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }),
                      let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let url = URL(fileURLWithPath: dir).appendingPathComponent("ui-\(section.rawValue).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                // cacheDisplay skips layer-hosted content (the glow previews), so also
                // render the Core Animation tree.
                if let layer = view.layer {
                    let scale = window.backingScaleFactor
                    let size = view.bounds.size
                    if let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                           bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                        ctx.scaleBy(x: scale, y: scale)
                        layer.presentation()?.render(in: ctx) ?? layer.render(in: ctx)
                        if let image = ctx.makeImage() {
                            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("layers-\(section.rawValue).png"))
                        }
                    }
                }
            }
            env.section = .nowPlaying
        }
    }
}
#endif
