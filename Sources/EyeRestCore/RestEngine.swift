import Foundation

public struct RestSettings: Equatable, Codable {
    public var workSeconds: Double
    public var restSeconds: Double
    public var snoozeSeconds: Double
    public init(workSeconds: Double = 1200, restSeconds: Double = 20, snoozeSeconds: Double = 300) {
        self.workSeconds = max(1, workSeconds)
        self.restSeconds = max(1, restSeconds)
        self.snoozeSeconds = max(1, snoozeSeconds)
    }
}

/// All time is supplied by the caller, keeping system sleep and UI independent of the rules.
public struct RestEngine: Equatable {
    public enum Phase: String { case working, due, resting, awaitingReturn }
    public private(set) var settings: RestSettings
    public private(set) var phase: Phase = .working
    public private(set) var remaining: Double
    public private(set) var restRemaining: Double
    public private(set) var snoozed = false
    public private(set) var paused = false
    public private(set) var suspended = false
    public private(set) var meetingRemaining: Double?
    public private(set) var meetingGraceRemaining: Double?
    public private(set) var completedRests = 0
    public var inMeeting: Bool { meetingRemaining != nil || meetingGraceRemaining != nil }
    public var shouldShowOverlay: Bool { (phase == .due || phase == .resting) && !inMeeting && !paused && !suspended }
    public var isDue: Bool { phase == .due }

    public init(settings: RestSettings = .init()) {
        self.settings = settings
        remaining = settings.workSeconds
        restRemaining = settings.restSeconds
    }

    public mutating func advance(by elapsed: Double) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        guard !suspended else { return }
        advanceMeeting(by: elapsed)
        guard !paused else { return }
        switch phase {
        case .working:
            remaining = max(0, remaining - elapsed)
            if remaining == 0 { phase = .due }
        case .due, .awaitingReturn: break // Neither a reminder nor waiting counts as computer use.
        case .resting:
            restRemaining = max(0, restRemaining - elapsed)
            if restRemaining == 0 { completeRest() }
        }
    }

    private mutating func advanceMeeting(by elapsed: Double) {
        if let grace = meetingGraceRemaining {
            let next = grace - elapsed
            meetingGraceRemaining = next > 0 ? next : nil
        } else if let meeting = meetingRemaining {
            let next = meeting - elapsed
            if next > 0 { meetingRemaining = next }
            else {
                meetingRemaining = nil
                let grace = 60 + next
                meetingGraceRemaining = grace > 0 ? grace : nil
            }
        }
    }

    public mutating func requestRest() {
        phase = .due
        remaining = 0
    }

    public mutating func startRest() {
        guard !inMeeting, !suspended, !paused else { return }
        phase = .resting
        restRemaining = settings.restSeconds
    }

    public mutating func inputOccurred() {
        guard !suspended, !paused else { return }
        switch phase {
        case .resting: restRemaining = settings.restSeconds
        case .awaitingReturn: resetCycle()
        case .working, .due: break
        }
    }

    public mutating func snooze() {
        phase = .working
        remaining = settings.snoozeSeconds
        restRemaining = settings.restSeconds
        snoozed = true
    }

    public mutating func startNextCycle() {
        guard phase == .awaitingReturn, !suspended else { return }
        paused = false
        resetCycle()
    }

    public mutating func skip() { resetCycle() }
    public mutating func setPaused(_ value: Bool) { paused = value }

    public mutating func startMeeting(seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        if phase == .resting { phase = .due; restRemaining = settings.restSeconds }
        meetingRemaining = seconds
        meetingGraceRemaining = nil
    }
    public mutating func endMeeting() {
        meetingRemaining = nil
        meetingGraceRemaining = nil
    }

    public mutating func suspend() { suspended = true }
    public mutating func resume(after awaySeconds: Double) {
        guard suspended else { return }
        suspended = false
        advanceMeeting(by: max(0, awaySeconds))
        if phase == .awaitingReturn { return }
        if awaySeconds >= settings.restSeconds {
            if phase == .resting { completeRest() }
            else { resetCycle() }
        }
    }

    public mutating func updateSettings(_ newSettings: RestSettings) {
        let previous = settings
        settings = newSettings
        if phase == .working {
            let oldLength = snoozed ? previous.snoozeSeconds : previous.workSeconds
            let newLength = snoozed ? newSettings.snoozeSeconds : newSettings.workSeconds
            remaining = max(0, newLength - max(0, oldLength - remaining))
            if remaining == 0 { phase = .due }
        }
        if phase == .resting {
            let spent = max(0, previous.restSeconds - restRemaining)
            restRemaining = max(0, newSettings.restSeconds - spent)
            if restRemaining == 0 { completeRest() }
        } else { restRemaining = newSettings.restSeconds }
    }

    private mutating func completeRest() {
        completedRests += 1
        phase = .awaitingReturn
        remaining = 0
        restRemaining = 0
        snoozed = false
    }
    private mutating func resetCycle() {
        phase = .working
        remaining = settings.workSeconds
        restRemaining = settings.restSeconds
        snoozed = false
    }
}
