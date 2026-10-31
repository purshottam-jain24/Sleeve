import AppKit
import AVFoundation
import IOKit.ps

@MainActor
/// Plays one looping, muted video in desktop-level windows behind every app.
///
/// Playback stops whenever nobody could see it: system or display sleep, screen locked,
/// screensaver, another user session, every window covered (full-screen apps), Low Power
/// Mode, and optionally on battery. Video decoding runs on the media engine.
final class WallpaperPlayer: NSObject {
    struct PauseReasons: OptionSet {
        let rawValue: Int
        static let systemSleep     = PauseReasons(rawValue: 1 << 0)
        static let displaySleep    = PauseReasons(rawValue: 1 << 1)
        static let screenLocked    = PauseReasons(rawValue: 1 << 2)
        static let screenSaver     = PauseReasons(rawValue: 1 << 3)
        static let sessionInactive = PauseReasons(rawValue: 1 << 4)
        static let occluded        = PauseReasons(rawValue: 1 << 5)
        static let lowPowerMode    = PauseReasons(rawValue: 1 << 6)
        static let user            = PauseReasons(rawValue: 1 << 7)
        static let onBattery       = PauseReasons(rawValue: 1 << 8)
        static let artwork         = PauseReasons(rawValue: 1 << 9)
    }

    /// While the song's artwork is the desktop picture, the video steps aside: its
    /// windows leave the screen and decoding stops.
    var isHiddenForArtwork = false {
        didSet {
            guard isHiddenForArtwork != oldValue else { return }
            set(.artwork, isHiddenForArtwork)
            if isHiddenForArtwork {
                windows.values.forEach { $0.orderOut(nil) }
            } else {
                rebuildWindows()
            }
        }
    }

    var showOnAllDisplays = true {
        didSet { rebuildWindows() }
    }

    var isUserPaused: Bool {
        get { pauseReasons.contains(.user) }
        set { set(.user, newValue) }
    }

    var pausesOnBattery = false {
        didSet { updateBatteryState() }
    }

    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var windows: [CGDirectDisplayID: WallpaperWindow] = [:]
    private var lowPowerObserver: NSObjectProtocol?

    private var pauseReasons: PauseReasons = [] {
        didSet { if pauseReasons != oldValue { updatePlayback() } }
    }

    override init() {
        super.init()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            pauseReasons.insert(.lowPowerMode)
        }
        observeSystemEvents()
        observePowerSource()
    }

    func play(url: URL) {
        looper?.disableLooping()
        player.removeAllItems()
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        looper = AVPlayerLooper(player: player, templateItem: item)
        rebuildWindows()
        updatePlayback()
    }

    func stop() {
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        windows.values.forEach { $0.orderOut(nil) }
        windows.removeAll()
        set(.occluded, false)
    }

    private func updatePlayback() {
        if pauseReasons.isEmpty && looper != nil {
            player.play()
        } else {
            player.pause()
        }
    }

    @objc private func rebuildWindows() {
        guard looper != nil else { return }
        guard !isHiddenForArtwork else { return }

        let targets = showOnAllDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        var updated: [CGDirectDisplayID: WallpaperWindow] = [:]
        for screen in targets {
            guard let id = screen.displayID else { continue }
            let window = windows.removeValue(forKey: id) ?? WallpaperWindow(player: player)
            window.place(on: screen)
            window.orderFrontRegardless()
            updated[id] = window
        }
        windows.values.forEach { $0.orderOut(nil) }
        windows = updated
        updateOcclusion()
    }

    @objc private func occlusionDidChange(_ note: Notification) {
        guard let window = note.object as? WallpaperWindow, windows.values.contains(window) else { return }
        updateOcclusion()
    }

    private func updateOcclusion() {
        let anyVisible = windows.values.contains { $0.occlusionState.contains(.visible) }
        set(.occluded, !anyVisible && !windows.isEmpty)
    }

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionDidResignActive), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionDidBecomeActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenSaverStarted), name: .init("com.apple.screensaver.didstart"), object: nil)
        distributed.addObserver(self, selector: #selector(screenSaverStopped), name: .init("com.apple.screensaver.didstop"), object: nil)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(rebuildWindows), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(occlusionDidChange), name: NSWindow.didChangeOcclusionStateNotification, object: nil)

        lowPowerObserver = center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.set(.lowPowerMode, ProcessInfo.processInfo.isLowPowerModeEnabled)
            }
        }
    }

    private func observePowerSource() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let manager = Unmanaged<WallpaperPlayer>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { manager.updateBatteryState() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func updateBatteryState() {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let type = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
        set(.onBattery, pausesOnBattery && type == kIOPMBatteryPowerKey)
    }

    private func set(_ reason: PauseReasons, _ active: Bool) {
        if active { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
    }

    @objc private func systemWillSleep() { set(.systemSleep, true) }
    @objc private func systemDidWake() { set(.systemSleep, false) }
    @objc private func screensDidSleep() { set(.displaySleep, true) }
    @objc private func screensDidWake() { set(.displaySleep, false) }
    @objc private func sessionDidResignActive() { set(.sessionInactive, true) }
    @objc private func sessionDidBecomeActive() { set(.sessionInactive, false) }
    @objc private func screenLocked() { set(.screenLocked, true) }
    @objc private func screenUnlocked() { set(.screenLocked, false) }
    @objc private func screenSaverStarted() { set(.screenSaver, true) }
    @objc private func screenSaverStopped() { set(.screenSaver, false) }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
