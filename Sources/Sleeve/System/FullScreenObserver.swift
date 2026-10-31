import AppKit
import SwiftUI

/// Tracks whether the hosting window is in full screen and, while it is, auto-hides the
/// menu bar and Dock so the app fills the display like part of the system.
struct FullScreenObserver: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = { isFullScreen = $0 }
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onChange = { isFullScreen = $0 }
    }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            guard let window else { return }

            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange?(true) }
            })
            observers.append(center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated {
                    // Valid combination: auto-hiding the menu bar requires auto-hiding the Dock,
                    // and auto-hiding the toolbar requires full screen.
                    NSApp.presentationOptions = [.fullScreen, .autoHideToolbar, .autoHideMenuBar, .autoHideDock]
                }
            })
            observers.append(center.addObserver(forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange?(false) }
            })
            onChange?(window.styleMask.contains(.fullScreen))
        }
        // Observers are removed above when the view leaves its window.
    }
}
