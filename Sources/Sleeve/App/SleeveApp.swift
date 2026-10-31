import AppKit
import SwiftUI

@main
struct AfterglowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Listed first so it opens at launch.
        Window("Afterglow", id: MainWindow.id) {
            MainWindow()
                .environment(appDelegate.environment)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands {
            AppCommands(environment: appDelegate.environment)
        }

        MenuBarExtra(isInserted: menuBarIconBinding) {
            MenuBarPanel()
                .environment(appDelegate.environment)
        } label: {
            MenuBarLabel(nowPlaying: appDelegate.environment.nowPlaying)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIconBinding: Binding<Bool> {
        let settings = appDelegate.environment.settings
        return Binding(
            get: { settings.settings.general.showMenuBarIcon },
            set: { newValue in
                // MenuBarExtra writes this binding back on every update. Writing an
                // unchanged value would still invalidate observers, re-render the scene and
                // write again: a loop that pinned a CPU core.
                guard settings.settings.general.showMenuBarIcon != newValue else { return }
                settings.settings.general.showMenuBarIcon = newValue
            }
        )
    }
}

private struct AppCommands: Commands {
    var environment: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                environment.section = .settings
                openWindow(id: MainWindow.id)
            }
            .keyboardShortcut(",")
        }
        CommandMenu("Playback") {
            // Space is handled by the playback screens so it never steals typing.
            Button("Play/Pause") { environment.nowPlaying.perform(.playPause) }
            Button("Next Track") { environment.nowPlaying.perform(.next) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous Track") { environment.nowPlaying.perform(.previous) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
        }
        CommandMenu("Go") {
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) {
                    environment.section = section
                    openWindow(id: MainWindow.id)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()
    /// Captured from the main window so a Dock click can reopen it after it was closed.
    var openMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        SnapshotTour.runIfRequested(environment)
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the window keeps the glow, menu bar item and playback detection running.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { openMainWindow?() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.shutdown()
    }
}
