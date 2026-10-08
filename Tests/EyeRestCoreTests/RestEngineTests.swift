import Foundation
import EyeRestCore

struct RestEngineTests {
    func testReminderWaitsForExplicitStartAndInputRestartsRest() {
        var e = RestEngine()
        e.advance(by: 1200)
        expectTrue(e.shouldShowOverlay)
        e.advance(by: 30)
        expectEqual(e.phase, .due)
        expectEqual(e.completedRests, 0)
        e.startRest()
        e.advance(by: 12)
        expectEqual(e.restRemaining, 8)
        e.inputOccurred()
        expectEqual(e.restRemaining, 20)
        e.advance(by: 20)
        expectEqual(e.phase, .awaitingReturn)
        expectEqual(e.remaining, 0)
        expectFalse(e.shouldShowOverlay)
        expectEqual(e.completedRests, 1)
    }
    func testMeetingAccumulatesUseAndWaitsThroughGrace() {
        var e = RestEngine()
        e.startMeeting(seconds: 1800)
        e.advance(by: 1200)
        expectTrue(e.isDue)
        expectFalse(e.shouldShowOverlay)
        e.advance(by: 600)
        expectEqual(e.meetingGraceRemaining, 60)
        expectFalse(e.shouldShowOverlay)
        e.advance(by: 59)
        expectFalse(e.shouldShowOverlay)
        e.advance(by: 1)
        expectFalse(e.inMeeting)
        expectTrue(e.shouldShowOverlay)
    }
    func testRenewingMeetingDuringGracePreventsOverlay() {
        var e = RestEngine()
        e.startMeeting(seconds: 1200)
        e.advance(by: 1200)
        e.startMeeting(seconds: 900)
        e.advance(by: 30)
        expectEqual(e.meetingRemaining, 870)
        expectNil(e.meetingGraceRemaining)
        expectFalse(e.shouldShowOverlay)
        e.endMeeting()
        expectTrue(e.shouldShowOverlay)
    }
    func testSleepDoesNotAccumulateUseAndLongSleepResets() {
        var e = RestEngine()
        e.advance(by: 1190)
        e.suspend()
        e.advance(by: 10)
        expectEqual(e.remaining, 10)
        e.resume(after: 10)
        expectEqual(e.remaining, 10)
        e.suspend()
        e.resume(after: 20)
        expectEqual(e.remaining, 1200)
        expectEqual(e.completedRests, 0)
    }
    func testShortLockPreservesRestAndManualPause() {
        var e = RestEngine()
        e.startRest()
        e.advance(by: 12)
        e.setPaused(true)
        e.suspend()
        e.resume(after: 5)
        expectTrue(e.paused)
        expectEqual(e.restRemaining, 8)
        e.setPaused(false)
        e.advance(by: 8)
        expectEqual(e.completedRests, 1)
    }
    func testSnoozeAndSkipAreDifferentAndPauseKeepsRemaining() {
        var e = RestEngine()
        e.advance(by: 1200)
        e.snooze()
        expectEqual(e.remaining, 300)
        e.advance(by: 10)
        e.setPaused(true)
        e.advance(by: 100)
        expectEqual(e.remaining, 290)
        e.setPaused(false)
        e.advance(by: 290)
        expectTrue(e.shouldShowOverlay)
        e.skip()
        expectEqual(e.remaining, 1200)
        expectFalse(e.snoozed)
    }
    func testLargeMeetingTickCrossesBothDeadlineAndGrace() {
        var e = RestEngine()
        e.startMeeting(seconds: 60)
        e.advance(by: 1200)
        expectFalse(e.inMeeting)
        expectTrue(e.shouldShowOverlay)
    }
    func testSettingsPreserveElapsedTimeAndNeverForgiveOverdueRest() {
        var e = RestEngine()
        e.advance(by: 600)
        e.updateSettings(.init(workSeconds: 1800))
        expectEqual(e.remaining, 1200)
        e.advance(by: 1200)
        e.updateSettings(.init(workSeconds: 3600))
        expectTrue(e.isDue)
    }
    func testStartingMeetingInterruptsActiveRestWithoutCountingIt() {
        var e = RestEngine()
        e.startRest()
        e.advance(by: 12)
        e.startMeeting(seconds: 900)
        expectEqual(e.phase, .due)
        expectEqual(e.completedRests, 0)
        e.endMeeting()
        expectTrue(e.shouldShowOverlay)
    }
    func testSuspendedMeetingElapsedTimeIsCountedExactlyOnce() {
        var e = RestEngine()
        e.startMeeting(seconds: 1800)
        e.advance(by: 1200)
        e.suspend()
        e.advance(by: 10)
        expectEqual(e.meetingRemaining, 600)
        e.resume(after: 20)
        expectEqual(e.meetingRemaining, 580)
        e.resume(after: 20)
        expectEqual(e.meetingRemaining, 580)
        expectEqual(e.remaining, 1200)
    }
    func testCompletedRestWaitsThroughTimeThenActivityStartsCycle() {
        var e = RestEngine()
        e.startRest()
        e.advance(by: 20)
        e.advance(by: 3600)
        expectEqual(e.phase, .awaitingReturn)
        expectEqual(e.remaining, 0)
        expectEqual(e.completedRests, 1)
        expectFalse(e.shouldShowOverlay)
        e.inputOccurred()
        expectEqual(e.phase, .working)
        expectEqual(e.remaining, 1200)
        e.advance(by: 15)
        e.startNextCycle() // Repeated confirmation must not forgive already-used time.
        expectEqual(e.remaining, 1185)
    }
    func testLockAfterCompletedRestKeepsWaitingAndSettingsApplyAtConfirmation() {
        var e = RestEngine()
        e.startRest()
        e.advance(by: 20)
        e.suspend()
        e.resume(after: 1800)
        e.updateSettings(.init(workSeconds: 1800, restSeconds: 30))
        expectEqual(e.phase, .awaitingReturn)
        expectEqual(e.remaining, 0)
        e.startNextCycle()
        expectEqual(e.remaining, 1800)
        expectEqual(e.restRemaining, 30)
    }
    func testLongLockDuringActiveRestFinishesIntoWaiting() {
        var e = RestEngine()
        e.startRest()
        e.advance(by: 5)
        e.suspend()
        e.resume(after: 60)
        expectEqual(e.phase, .awaitingReturn)
        expectEqual(e.completedRests, 1)
        expectFalse(e.shouldShowOverlay)
        e.suspend()
        e.resume(after: 60)
        expectEqual(e.completedRests, 1)
        expectEqual(e.phase, .awaitingReturn)
    }
    func testMeetingAndSettingsCannotAutomaticallyStartCompletedCycle() {
        var e = RestEngine()
        e.startRest()
        e.advance(by: 15)
        e.updateSettings(.init(restSeconds: 10))
        expectEqual(e.phase, .awaitingReturn)
        expectEqual(e.completedRests, 1)
        e.startMeeting(seconds: 60)
        e.advance(by: 130)
        e.endMeeting()
        expectEqual(e.phase, .awaitingReturn)
        expectFalse(e.shouldShowOverlay)
        e.setPaused(true)
        e.startNextCycle()
        expectFalse(e.paused)
        expectEqual(e.remaining, 1200)
    }
    func testReturnActivityRespectsPauseAndSuspension() {
        var e = RestEngine()
        e.startRest()
        e.advance(by: 20)
        e.setPaused(true)
        e.inputOccurred()
        expectEqual(e.phase, .awaitingReturn)
        e.setPaused(false)
        e.suspend()
        e.inputOccurred()
        expectEqual(e.phase, .awaitingReturn)
        e.resume(after: 60)
        expectEqual(e.phase, .awaitingReturn)
        e.inputOccurred()
        expectEqual(e.phase, .working)
        expectEqual(e.remaining, 1200)
        e.advance(by: 15)
        e.inputOccurred()
        expectEqual(e.remaining, 1185)
    }
    func testNonFiniteOrNegativeTimeCannotDamageEngine() {
        var e = RestEngine()
        e.advance(by: .infinity)
        e.advance(by: -1)
        e.advance(by: .nan)
        expectEqual(e.remaining, 1200)
    }
}

private func fail(_ message: String, file: StaticString, line: UInt) {
    fputs("FAIL \(file):\(line) \(message)\n", stderr)
    exit(1)
}
private func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) {
    if a != b { fail("\(a) != \(b)", file: file, line: line) }
}
private func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value { fail("Expected true", file: file, line: line) }
}
private func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if value { fail("Expected false", file: file, line: line) }
}
private func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value != nil { fail("Expected nil", file: file, line: line) }
}
@main enum Checks {
    static func main() {
        let tests = RestEngineTests()
        tests.testReminderWaitsForExplicitStartAndInputRestartsRest()
        print("PASS testReminderWaitsForExplicitStartAndInputRestartsRest")
        tests.testMeetingAccumulatesUseAndWaitsThroughGrace()
        print("PASS testMeetingAccumulatesUseAndWaitsThroughGrace")
        tests.testRenewingMeetingDuringGracePreventsOverlay()
        print("PASS testRenewingMeetingDuringGracePreventsOverlay")
        tests.testSleepDoesNotAccumulateUseAndLongSleepResets()
        print("PASS testSleepDoesNotAccumulateUseAndLongSleepResets")
        tests.testShortLockPreservesRestAndManualPause()
        print("PASS testShortLockPreservesRestAndManualPause")
        tests.testSnoozeAndSkipAreDifferentAndPauseKeepsRemaining()
        print("PASS testSnoozeAndSkipAreDifferentAndPauseKeepsRemaining")
        tests.testLargeMeetingTickCrossesBothDeadlineAndGrace()
        print("PASS testLargeMeetingTickCrossesBothDeadlineAndGrace")
        tests.testSettingsPreserveElapsedTimeAndNeverForgiveOverdueRest()
        print("PASS testSettingsPreserveElapsedTimeAndNeverForgiveOverdueRest")
        tests.testStartingMeetingInterruptsActiveRestWithoutCountingIt()
        print("PASS testStartingMeetingInterruptsActiveRestWithoutCountingIt")
        tests.testSuspendedMeetingElapsedTimeIsCountedExactlyOnce()
        print("PASS testSuspendedMeetingElapsedTimeIsCountedExactlyOnce")
        tests.testNonFiniteOrNegativeTimeCannotDamageEngine()
        print("PASS testNonFiniteOrNegativeTimeCannotDamageEngine")
        tests.testCompletedRestWaitsThroughTimeThenActivityStartsCycle()
        print("PASS testCompletedRestWaitsThroughTimeThenActivityStartsCycle")
        tests.testLockAfterCompletedRestKeepsWaitingAndSettingsApplyAtConfirmation()
        print("PASS testLockAfterCompletedRestKeepsWaitingAndSettingsApplyAtConfirmation")
        tests.testLongLockDuringActiveRestFinishesIntoWaiting()
        print("PASS testLongLockDuringActiveRestFinishesIntoWaiting")
        tests.testMeetingAndSettingsCannotAutomaticallyStartCompletedCycle()
        print("PASS testMeetingAndSettingsCannotAutomaticallyStartCompletedCycle")
        tests.testReturnActivityRespectsPauseAndSuspension()
        print("PASS testReturnActivityRespectsPauseAndSuspension")
        print("16 lifecycle checks passed")
    }
}
