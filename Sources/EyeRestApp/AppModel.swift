import AppKit
import SwiftUI
import ServiceManagement
import CoreGraphics
import EyeRestCore

struct Preferences: Codable, Equatable {
    enum Appearance: String, Codable, CaseIterable {
        case system, light, dark
        var title: String { switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" } }
        var scheme: ColorScheme? { switch self { case .system: return nil; case .light: return .light; case .dark: return .dark } }
        var appKit: NSAppearance? { switch self { case .system: return nil; case .light: return NSAppearance(named: .aqua); case .dark: return NSAppearance(named: .darkAqua) } }
    }
    var timing = RestSettings()
    var appearance: Appearance = .system
    var animateTutu = true
    var playSound = true
    var meetingMinutes = 30
}

/// Reads event counts, never key codes, text, window content, or audio.
struct InputActivity {
    private let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
    private var baseline: [UInt32] = []
    private let eventCount: (CGEventType) -> UInt32
    init(eventCount: @escaping (CGEventType) -> UInt32 = {
        CGEventSource.counterForEventType(.combinedSessionState, eventType: $0)
    }) { self.eventCount = eventCount }
    mutating func reset() { baseline = counts() }
    mutating func changed() -> Bool {
        let next = counts()
        let changed = !baseline.isEmpty && baseline != next
        baseline = next
        return changed
    }
    private var movementBaseline: [UInt32] = []
    mutating func resetReturnActivity() {
        reset()
        movementBaseline = movementCounts()
    }
    mutating func returnActivityChanged() -> Bool {
        let inputChanged = changed()
        let next = movementCounts()
        let moved = !movementBaseline.isEmpty && movementBaseline != next
        movementBaseline = next
        return inputChanged || moved
    }
    private func movementCounts() -> [UInt32] {
        [CGEventType.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].map(eventCount)
    }
    private func counts() -> [UInt32] {
        types.map(eventCount)
    }
}

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var engine: RestEngine
    @Published var preferences: Preferences
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var loginError: String?
    @Published var resetMessage = false
    var onChange: (() -> Void)?
    var showSettings: (() -> Void)?
    var dismissPopover: (() -> Void)?
    private let defaults: UserDefaults?
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var input = InputActivity()
    private var interruptionUntil = Date.distantPast
    private var suspensionReasons = Set<String>()
    private var suspendedAt: Date?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var localMonitor: Any?
    let diagnostic: Bool

    init(diagnostic: Bool = false) {
        self.diagnostic = diagnostic
        // Keep smoke timing deterministic while the user continues using their Mac.
        // The real local monitor and injected activity-counter checks remain exercised.
        input = diagnostic ? InputActivity(eventCount: { _ in 0 }) : InputActivity()
        defaults = diagnostic ? nil : .standard
        var loaded = Preferences()
        if let data = defaults?.data(forKey: "EyeRest.preferences"), let stored = try? JSONDecoder().decode(Preferences.self, from: data) {
            loaded = stored
        }
        // Keep restored settings inside the supported UI range.
        loaded.timing = RestSettings(
            workSeconds: min(7200, max(60, loaded.timing.workSeconds)),
            restSeconds: min(300, max(10, loaded.timing.restSeconds)),
            snoozeSeconds: min(1800, max(60, loaded.timing.snoozeSeconds)))
        preferences = loaded
        engine = RestEngine(settings: loaded.timing)
        if !diagnostic { refreshLoginStatus() }
    }

    func start() {
        input.reset()
        lastTick = ProcessInfo.processInfo.systemUptime
        if !diagnostic { startTimer() }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.suspend("system") }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.resume("system") }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.suspend("display") }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.resume("display") }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.suspend("session") }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.resume("session") }
        // Screen-lock notifications complement workspace session and display events.
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.suspend("lock") }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.resume("lock") }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, self.engine.phase == .resting { self.restartRest() }
            }
            return event
        }
    }

    func startTimer() {
        timer?.invalidate()
        lastTick = ProcessInfo.processInfo.systemUptime
        timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping (AppModel) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        observers.append((center, token))
    }

    func stop() {
        timer?.invalidate()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
    }

    private func tick() {
        let now = Date()
        let instant = ProcessInfo.processInfo.systemUptime
        let elapsed = max(0, instant - lastTick)
        lastTick = instant
        if engine.suspended { return }
        let oldCompleted = engine.completedRests
        if engine.phase == .resting && input.changed() {
            restartRest()
            onChange?()
            return
        }
        if engine.phase == .awaitingReturn {
            if input.returnActivityChanged() {
                returnActivityOccurred()
                return
            }
        } else if engine.phase != .resting { input.resetReturnActivity() }
        if now >= interruptionUntil { resetMessage = false }
        // A delayed main loop must not count unobserved time as a completed active rest.
        if engine.phase == .resting && elapsed > 2 { engine.inputOccurred() }
        else { engine.advance(by: min(elapsed, 86400)) }
        if engine.completedRests > oldCompleted {
            // Only activity after completion may start the next cycle.
            input.resetReturnActivity()
            if preferences.playSound && !engine.inMeeting {
                if let sound = NSSound(named: "Pop") { sound.volume = 0.3; sound.play() }
            }
        }
        onChange?()
    }

    private func restartRest() {
        engine.inputOccurred()
        resetMessage = true
        interruptionUntil = Date().addingTimeInterval(1.5)
        lastTick = ProcessInfo.processInfo.systemUptime
        input.reset()
    }

    private func mutate(_ action: (inout RestEngine) -> Void) {
        action(&engine)
        input.resetReturnActivity()
        lastTick = ProcessInfo.processInfo.systemUptime
        onChange?()
    }
    func requestRest() { mutate { $0.requestRest() } }
    func beginRest() { resetMessage = false; mutate { $0.startRest() } }
    func startNextCycle() { mutate { $0.startNextCycle() }; dismissPopover?() }
    func returnActivityOccurred() {
        guard engine.phase == .awaitingReturn, !engine.paused, !engine.suspended else { return }
        mutate { $0.inputOccurred() }
        dismissPopover?()
    }
    func keepResting() {
        input.resetReturnActivity() // The dismiss button itself is not a return to work.
        dismissPopover?()
    }
    func snooze() { mutate { $0.snooze() } }
    func skip() { mutate { $0.skip() } }
    func togglePause() { mutate { $0.setPaused(!$0.paused) } }
    func startMeeting(minutes: Int? = nil) {
        let minutes = minutes ?? preferences.meetingMinutes
        mutate { $0.startMeeting(seconds: Double(minutes) * 60) }
    }
    func endMeeting() { mutate { $0.endMeeting() } }

    func suspend(_ reason: String) {
        guard !suspensionReasons.contains(reason) else { return }
        suspensionReasons.insert(reason)
        if suspendedAt == nil {
            suspendedAt = Date()
            mutate { $0.suspend() }
        }
    }
    func resume(_ reason: String) {
        suspensionReasons.remove(reason)
        guard suspensionReasons.isEmpty, let since = suspendedAt else { return }
        suspendedAt = nil
        mutate { $0.resume(after: max(0, Date().timeIntervalSince(since))) }
    }

    var menuBarState: (symbol: String, title: String) {
        if engine.suspended { return ("moon.zzz", "睡眠中") }
        if engine.paused { return ("pause.circle", "已暂停") }
        if engine.meetingGraceRemaining != nil { return ("clock.badge.exclamationmark", "会议即将结束，可续时") }
        if engine.inMeeting { return (engine.isDue ? "exclamationmark.bubble" : "person.2", engine.isDue ? "会议中 · 该休息了" : "会议中") }
        switch engine.phase {
        case .working: return (engine.snoozed ? "clock.arrow.circlepath" : "hourglass", engine.snoozed ? "延后提醒中" : "计时中")
        case .due: return ("exclamationmark.circle", "该休息一下了")
        case .resting: return ("cup.and.saucer", "休息中")
        case .awaitingReturn: return ("checkmark.circle", "休息完成 · 操作电脑后自动计时")
        }
    }

    func savePreferences() {
        if let data = try? JSONEncoder().encode(preferences) { defaults?.set(data, forKey: "EyeRest.preferences") }
        let previousPhase = engine.phase
        engine.updateSettings(preferences.timing)
        if previousPhase != .awaitingReturn && engine.phase == .awaitingReturn { input.resetReturnActivity() }
        NSApp.appearance = preferences.appearance.appKit
        onChange?()
    }

    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }
    func setLogin(_ value: Bool) {
        guard !diagnostic else { return }
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = "未能更新登录启动：\(error.localizedDescription)" }
        refreshLoginStatus()
    }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    func diagnosticAdvance(_ seconds: Double) { mutate { $0.advance(by: seconds) } }
    static func format(_ seconds: Double) -> String {
        let total = Int(ceil(max(0, seconds)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
