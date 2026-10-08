import AppKit
import SwiftUI
import EyeRestCore

final class RestPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { super.keyDown(with: event) }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let diagnostic = CommandLine.arguments.contains("--smoke-test")
    lazy var model = AppModel(diagnostic: diagnostic)
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var overlays: [RestPanel] = []
    private var previousApp: NSRunningApplication?
    private var displayObserver: NSObjectProtocol?
    private var lastIconState = ""
    private var syncPending = false
    private var returnPromptShown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        NSApp.appearance = model.preferences.appearance.appKit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.setAccessibilityLabel("休息一下")
        popover.behavior = .transient
        popover.animates = !diagnostic
        let controller = NSHostingController(rootView: MenuPopover(model: model))
        controller.sizingOptions = []
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 355)
        controller.view.autoresizingMask = [.width, .height]
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 320, height: 355)
        model.onChange = { [weak self] in self?.scheduleSync() }
        model.dismissPopover = { [weak self] in self?.popover.performClose(nil) }
        model.showSettings = { [weak self] in self?.openSettings() }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.model.engine.shouldShowOverlay { self.hideOverlays(); self.showOverlays() }
            }
        }
        syncWindows()
        if diagnostic { runSmokeTest() }
        else {
            model.start()
            if !UserDefaults.standard.bool(forKey: "EyeRest.hasLaunched") {
                UserDefaults.standard.set(true, forKey: "EyeRest.hasLaunched")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.togglePopover() }
            }
        }
    }

    private func configureMainMenu() {
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "设置…", action: #selector(settingsAction), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出休息一下", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        resizePopover()
        popover.behavior = model.engine.phase == .awaitingReturn ? .applicationDefined : .transient
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    @objc private func settingsAction() { openSettings() }

    private func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 640), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "设置"
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func scheduleSync() {
        guard !syncPending else { return }
        syncPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncPending = false
            self.syncWindows()
        }
    }

    private func resizePopover() {
        let height: CGFloat = model.engine.phase == .awaitingReturn ? 505 : model.engine.inMeeting ? 500 : 355
        if popover.contentSize.height != height {
            popover.contentSize = NSSize(width: 320, height: height)
            popover.contentViewController?.view.setFrameSize(NSSize(width: 320, height: height))
        }
    }

    private func syncWindows() {
        if popover.isShown { resizePopover() }
        let state = model.menuBarState
        if state.symbol != lastIconState {
            lastIconState = state.symbol
            let image = NSImage(systemSymbolName: state.symbol, accessibilityDescription: state.title)
            image?.isTemplate = true
            statusItem.button?.image = image
        }
        statusItem.button?.toolTip = "休息一下 · \(state.title)"
        statusItem.button?.setAccessibilityLabel("休息一下 · \(state.title)")
        if model.engine.shouldShowOverlay {
            if overlays.isEmpty { showOverlays() }
        } else if !overlays.isEmpty { hideOverlays() }
        if model.engine.phase != .awaitingReturn { returnPromptShown = false }
        else if !returnPromptShown && !model.engine.suspended && !model.engine.paused && !model.engine.inMeeting {
            returnPromptShown = true
            popover.performClose(nil)
            resizePopover()
            popover.behavior = .applicationDefined
            // Completion should not steal keyboard focus from the user's previous app.
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    private func showOverlays() {
        guard overlays.isEmpty else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        popover.performClose(nil)
        let mouse = NSEvent.mouseLocation
        var keyPanel: RestPanel?
        for screen in NSScreen.screens {
            let panel = RestPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isFloatingPanel = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.title = "休息一下"
            panel.contentViewController = NSHostingController(rootView: RestOverlay(model: model))
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            overlays.append(panel)
            if screen.frame.contains(mouse) { keyPanel = panel }
        }
        NSApp.activate(ignoringOtherApps: true)
        (keyPanel ?? overlays.first)?.makeKeyAndOrderFront(nil)
    }
    private func hideOverlays() {
        overlays.forEach { $0.orderOut(nil); $0.close() }
        overlays.removeAll()
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
           settingsWindow?.isVisible != true, !popover.isShown {
            previousApp?.activate(options: [])
        }
        previousApp = nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        hideOverlays()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Diagnostic mode is isolated from preferences and login registration. It uses the real native views.
    private func runSmokeTest() {
        let directory = CommandLine.arguments.firstIndex(of: "--output").flatMap { index in
            index + 1 < CommandLine.arguments.count ? CommandLine.arguments[index + 1] : nil
        } ?? "/tmp/eye-rest-smoke"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        func log(_ value: String) { print(value); fflush(stdout) }
        // Exercise the exact production counter reader without posting input to the desktop.
        var counts: [UInt32: UInt32] = [:]
        var activity = InputActivity(eventCount: { counts[$0.rawValue, default: 0] })
        activity.resetReturnActivity()
        counts[CGEventType.mouseMoved.rawValue] = 1
        guard !activity.changed(), activity.returnActivityChanged(), !activity.returnActivityChanged() else {
            log("FAIL movement must signal return once, never interrupt rest"); exit(1)
        }
        for type in [CGEventType.keyDown, .leftMouseDown, .scrollWheel, .leftMouseDragged] {
            counts[type.rawValue, default: 0] += 1
            guard activity.returnActivityChanged(), !activity.returnActivityChanged() else {
                log("FAIL return activity counter \(type)"); exit(1)
            }
        }
        counts[CGEventType.keyDown.rawValue, default: 0] += 1
        activity.resetReturnActivity()
        guard !activity.returnActivityChanged() else {
            log("FAIL stale activity crossed reset baseline"); exit(1)
        }
        log("PASS activity counters: keyboard, click, scroll, move, drag, reset baseline")
        for symbol in ["hourglass", "cup.and.saucer", "checkmark.circle", "pause.circle", "person.2", "clock.badge.exclamationmark", "exclamationmark.circle", "exclamationmark.bubble", "clock.arrow.circlepath", "moon.zzz"] {
            guard NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil else {
                log("FAIL missing status symbol \(symbol)"); exit(1)
            }
        }
        log("PASS all menu bar status symbols")
        func capture(_ view: NSView, _ name: String) {
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { log("FAIL bitmap \(name)"); return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                do { try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")); log("Captured \(name)") }
                catch { log("FAIL save \(error)") }
            }
        }
        func later(_ seconds: Double, _ action: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { action() } }
        model.start()
        model.preferences.appearance = .light
        model.savePreferences()
        later(0.2) { self.togglePopover() }
        later(0.6) {
            if let view = self.popover.contentViewController?.view { capture(view, "menu-light") }
            self.openSettings()
        }
        later(1.1) {
            capture(self.settingsWindow!.contentView!, "settings-light")
            self.model.requestRest()
            later(0.7) {
                guard let panel = self.overlays.first else { log("FAIL overlay absent"); exit(1) }
                capture(panel.contentView!, "overlay-light")
                log("Overlay count: \(self.overlays.count); displays: \(NSScreen.screens.count)")
                log("Tutu rows: \(TutuFrames.frames.count); frames: \(TutuFrames.frames.map(\.count))")
                log("Session input counts: \(CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)) / \(CGEventSource.counterForEventType(.combinedSessionState, eventType: .leftMouseDown))")
                self.model.preferences.appearance = .dark
                self.model.savePreferences()
                later(0.7) {
                    capture(panel.contentView!, "overlay-dark")
                    capture(self.settingsWindow!.contentView!, "settings-dark")
                    self.model.beginRest()
                    // Render a fresh native view with production timings for documentation.
                    // No desktop capture and no short smoke-test duration in this image.
                    let restingPreview = NSHostingView(rootView: RestOverlay(model: self.model))
                    restingPreview.frame = panel.contentView!.bounds
                    capture(restingPreview, "resting-default-dark")
                    self.model.diagnosticAdvance(12)
                    log("Rest after 12s: \(self.model.engine.restRemaining)")
                    self.model.diagnosticAdvance(8)
                    log("Rest completed, wants overlay: \(self.model.engine.shouldShowOverlay), next: \(self.model.engine.remaining)")
                    self.model.startNextCycle()
                    self.model.startMeeting()
                    self.model.diagnosticAdvance(1200)
                    log("Meeting due: \(self.model.engine.isDue), wants overlay: \(self.model.engine.shouldShowOverlay)")
                    self.model.diagnosticAdvance(600)
                    log("Meeting grace: \(self.model.engine.meetingGraceRemaining ?? -1)")
                    self.togglePopover()
                    later(0.5) {
                        if let view = self.popover.contentViewController?.view { capture(view, "meeting-grace") }
                        self.model.startMeeting(minutes: 15)
                        log("Renewed meeting: \(self.model.engine.meetingRemaining ?? -1), wants overlay: \(self.model.engine.shouldShowOverlay)")
                        self.model.endMeeting()
                        log("Meeting ended, wants overlay: \(self.model.engine.shouldShowOverlay)")
                        self.model.snooze()
                        log("Snoozed: \(self.model.engine.remaining), wants overlay: \(self.model.engine.shouldShowOverlay)")
                        self.model.suspend("diagnostic")
                        self.model.resume("diagnostic")
                        self.model.skip()
                        // Close the settings host before using sub-second diagnostic timings,
                        // which are intentionally outside the production settings controls.
                        self.settingsWindow?.close()
                        self.settingsWindow?.contentViewController = nil
                        self.settingsWindow = nil
                        self.popover.performClose(nil)
                        // Exercise the real timer and event monitor without changing saved preferences.
                        self.model.preferences.timing = RestSettings(workSeconds: 1, restSeconds: 2, snoozeSeconds: 1)
                        self.model.preferences.playSound = false
                        self.model.savePreferences()
                        self.model.skip()
                        self.model.startTimer()
                        later(1.3) {
                            log("Real timer due: \(self.model.engine.isDue), overlays: \(self.overlays.count)")
                            self.model.beginRest()
                            later(0.7) {
                                let before = self.model.engine.restRemaining
                                if let keyWindow = NSApp.keyWindow, let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: keyWindow.windowNumber, context: nil, characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15) {
                                    NSApp.sendEvent(key)
                                }
                                log("Local key resets rest: \(before) → \(self.model.engine.restRemaining)")
                                capture(self.overlays.first!.contentView!, "active-rest")
                                later(2.5) {
                                    log("Real timer rest completed: \(self.model.engine.completedRests), overlays: \(self.overlays.count)")
                                    guard self.model.engine.phase == .awaitingReturn, self.overlays.isEmpty, self.popover.isShown else {
                                        log("FAIL return prompt missing"); exit(1)
                                    }
                                    self.model.preferences.timing = RestSettings()
                                    self.model.savePreferences()
                                    capture(self.popover.contentViewController!.view, "return-ready-dark")
                                    self.model.diagnosticAdvance(3600)
                                    log("Waiting after one hour: \(self.model.engine.phase), remaining: \(self.model.engine.remaining)")
                                    self.model.preferences.appearance = .light
                                    self.model.savePreferences()
                                    later(0.3) {
                                        capture(self.popover.contentViewController!.view, "return-ready-light")
                                        self.model.dismissPopover?()
                                        self.model.diagnosticAdvance(60)
                                        later(0.3) {
                                            log("Dismissed prompt: shown=\(self.popover.isShown), phase=\(self.model.engine.phase), presented=\(self.returnPromptShown)")
                                            guard !self.popover.isShown, self.model.engine.phase == .awaitingReturn else {
                                                log("FAIL dismissed prompt restarted or reopened"); exit(1)
                                            }
                                            self.togglePopover()
                                            self.model.preferences.timing = RestSettings()
                                            self.model.savePreferences()
                                            self.model.returnActivityOccurred()
                                            log("Activity next cycle: \(self.model.engine.phase), remaining: \(self.model.engine.remaining)")
                                            guard self.model.engine.phase == .working, self.model.engine.remaining == 1200 else {
                                                log("FAIL activity did not restart cycle"); exit(1)
                                            }
                                            log("Menu bar state: \(self.model.menuBarState.symbol) · \(self.model.menuBarState.title)")
                                            self.model.preferences.appearance = .system
                                            self.model.savePreferences()
                                            log("Follow system: \(NSApp.appearance == nil)")
                                            log("SMOKE TEST COMPLETE")
                                            NSApp.terminate(nil)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { application.run() }
}
