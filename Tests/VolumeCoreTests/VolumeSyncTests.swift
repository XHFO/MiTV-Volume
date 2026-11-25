import XCTest
@testable import VolumeCore

@MainActor final class FakeDevice: VolumeDevice {
    var state = DriverState()
    var confirms = 0
    func read() throws -> DriverState { state }
    func command(_ scalar: Float) { state.revision += 1; state.scalar = scalar }
    func confirm(_ volume: Float, revision: UInt64) throws -> Bool {
        guard state.revision == revision else { return false }
        state.scalar = volume; confirms += 1; return true
    }
}
@MainActor final class FakeTV: VolumeTV {
    var volume = 20
    var maximum = 100
    var online = true
    var supported = true
    var ignoreSet = false
    var ignoreStep = false
    var sets: [Int] = []
    var steps: [Bool] = []
    var onStep: (() -> Void)?
    var staleReads = 0
    var staleVolume = 20
    var onSet: (() -> Void)?
    var onRead: (() -> Void)?
    func read() async throws -> TVVolume {
        guard online else { throw VolumeError("离线") }
        onRead?(); onRead = nil
        if staleReads > 0 { staleReads -= 1; return try TVVolume(value: staleVolume, maximum: maximum) }
        return try TVVolume(value: volume, maximum: maximum)
    }
    func setAbsolute(_ value: Int) async throws -> Bool {
        guard online else { throw VolumeError("离线") }
        sets.append(value); onSet?(); onSet = nil
        if supported && !ignoreSet { volume = value }
        return supported
    }
    func step(up: Bool) async throws {
        guard online else { throw VolumeError("离线") }
        steps.append(up); onStep?(); onStep = nil
        if !ignoreStep { volume = max(0, min(maximum, volume + (up ? 1 : -1))) }
    }
}
final class VolumeSyncTests: XCTestCase {
    @MainActor func testStartupAdoptsTVWithoutWriting() async {
        let d = FakeDevice(), tv = FakeTV(); d.command(0.9)
        let s = VolumeSync(device: d, tv: tv); await s.tick()
        XCTAssertEqual(d.state.scalar, 0.2); XCTAssertTrue(tv.sets.isEmpty)
    }
    @MainActor func testRemoteChangesDoNotEcho() async {
        let d = FakeDevice(), tv = FakeTV(), s: VolumeSync
        s = VolumeSync(device: d, tv: tv); await s.tick()
        tv.volume = 41; await s.tick(); await s.tick()
        XCTAssertEqual(d.state.scalar, 0.41); XCTAssertTrue(tv.sets.isEmpty)
    }
    @MainActor func testLatestDragWinsAndQuantizesToTVSteps() async {
        let d = FakeDevice(), tv = FakeTV(); tv.maximum = 30
        let s = VolumeSync(device: d, tv: tv); await s.tick()
        d.command(0.2); d.command(0.4); d.command(0.55); await s.tick()
        XCTAssertEqual(tv.sets, [17]); XCTAssertEqual(d.state.scalar, Float(17) / 30)
    }
    @MainActor func testNewCommandDuringNetworkRequestIsNotOverwritten() async {
        let d = FakeDevice(), tv = FakeTV()
        let s = VolumeSync(device: d, tv: tv); await s.tick()
        d.command(0.4); tv.onSet = { d.command(0.8) }; await s.tick()
        XCTAssertEqual(d.state.scalar, 0.8)
        await s.tick(); XCTAssertEqual(tv.sets, [40, 80]); XCTAssertEqual(tv.volume, 80)
    }
    @MainActor func testNewCommandDuringPollIsNotOverwritten() async {
        let d = FakeDevice(), tv = FakeTV()
        let s = VolumeSync(device: d, tv: tv); await s.tick()
        tv.onRead = { d.command(0.6) }; await s.tick()
        XCTAssertEqual(d.state.scalar, 0.6); await s.tick(); XCTAssertEqual(tv.volume, 60)
    }
    @MainActor func testDisconnectDropsOldTargets() async {
        let d = FakeDevice(), tv = FakeTV()
        let s = VolumeSync(device: d, tv: tv); await s.tick()
        tv.online = false; d.command(0.9); await s.tick(); XCTAssertFalse(s.connected)
        tv.online = true; tv.volume = 12; await s.tick()
        XCTAssertEqual(d.state.scalar, 0.12); XCTAssertEqual(tv.volume, 12); XCTAssertTrue(tv.sets.isEmpty)
    }
    @MainActor func testFallbackReadsEveryStepAndCanReverse() async {
        let d = FakeDevice(), tv = FakeTV(); tv.supported = false
        let s = VolumeSync(device: d, tv: tv); await s.tick()
        d.command(0.24); await s.tick(); await s.tick()
        XCTAssertEqual(tv.volume, 21); XCTAssertEqual(d.state.scalar, 0.24)
        d.command(0.19); await s.tick(); await s.tick()
        XCTAssertEqual(tv.volume, 19); XCTAssertEqual(tv.steps, [true, false, false])
    }
    @MainActor func testFalseSuccessFallsBackAndStuckDeviceStops() async {
        let d = FakeDevice(), tv = FakeTV(); tv.ignoreSet = true; tv.ignoreStep = true
        let s = VolumeSync(device: d, tv: tv); await s.tick()
        d.command(0.3)
        for _ in 0..<10 { await s.tick() }
        XCTAssertEqual(tv.sets.count, 3); XCTAssertEqual(tv.steps.count, 3)
        XCTAssertFalse(s.hasPendingTarget); XCTAssertEqual(d.state.scalar, 0.2)
    }
    @MainActor func testOverlappingTicksDoNotDuplicateCommands() async {
        let d = FakeDevice(), tv = FakeTV()
        let s = VolumeSync(device: d, tv: tv); await s.tick(); d.command(0.5)
        let first = Task { await s.tick() }
        await Task.yield(); await s.tick(); await first.value
        XCTAssertEqual(tv.sets, [50])
    }
    @MainActor func testBurstWaitsForQuietAndSendsOnlyLatestTarget() async {
        let d = FakeDevice(), tv = FakeTV(); var clock: TimeInterval = 10
        let s = VolumeSync(device: d, tv: tv, quietInterval: 0.5, now: { clock })
        await s.tick(); let confirmations = d.confirms
        d.command(0.3); await s.tick()
        clock += 0.3; d.command(0.4); await s.tick()
        clock += 0.3; d.command(0.5); await s.tick()
        clock += 0.49; await s.tick()
        XCTAssertTrue(tv.sets.isEmpty); XCTAssertEqual(d.confirms, confirmations)
        XCTAssertEqual(d.state.scalar, 0.5)
        clock += 0.02; await s.tick()
        XCTAssertEqual(tv.sets, [50]); XCTAssertFalse(s.hasPendingTarget)
    }
    @MainActor func testNewInputInFlightStartsAnotherQuietWindow() async {
        let d = FakeDevice(), tv = FakeTV(); var clock: TimeInterval = 0
        let s = VolumeSync(device: d, tv: tv, quietInterval: 0.5, now: { clock })
        await s.tick(); d.command(0.3); await s.tick()
        clock = 0.6; tv.onSet = { d.command(0.4) }; await s.tick()
        XCTAssertEqual(d.state.scalar, 0.4)
        await s.tick(); clock = 1; await s.tick(); XCTAssertEqual(tv.sets, [30])
        clock = 1.2; await s.tick(); XCTAssertEqual(tv.sets, [30, 40])
    }
    @MainActor func testFallbackPreservesTargetBetweenShortcutPresses() async {
        let d = FakeDevice(), tv = FakeTV(); tv.supported = false
        var clock: TimeInterval = 0
        let s = VolumeSync(device: d, tv: tv, quietInterval: 0.5, now: { clock })
        await s.tick(); d.command(0.24); await s.tick(); clock = 1
        await s.tick(); await s.tick()
        XCTAssertEqual(tv.volume, 21); XCTAssertEqual(d.state.scalar, 0.24)
        d.command(d.state.scalar + 0.01); await s.tick()
        clock = 1.4; await s.tick(); XCTAssertEqual(tv.steps.count, 1)
        XCTAssertEqual(d.state.scalar, 0.25)
        clock = 2
        for _ in 0..<4 { await s.tick() }
        XCTAssertEqual(tv.volume, 25); XCTAssertEqual(d.state.scalar, 0.25)
        XCTAssertFalse(s.hasPendingTarget)
        tv.volume = 18; await s.tick(); XCTAssertEqual(d.state.scalar, 0.18)
    }
    @MainActor func testQuietWindowRefreshesRemoteBeforeChoosingDirection() async {
        let d = FakeDevice(), tv = FakeTV(); tv.supported = false
        var clock: TimeInterval = 0
        let s = VolumeSync(device: d, tv: tv, quietInterval: 0.5, now: { clock })
        await s.tick(); d.command(0.23); await s.tick()
        tv.volume = 24; clock = 1; await s.tick(); await s.tick()
        XCTAssertEqual(tv.steps, [false]); XCTAssertEqual(tv.volume, 23)
    }
    @MainActor func testUnplugDuringDelayDropsTargetOnReconnect() async {
        let d = FakeDevice(), tv = FakeTV(); var clock: TimeInterval = 0
        let s = VolumeSync(device: d, tv: tv, quietInterval: 0.5, now: { clock })
        await s.tick(); d.command(0.9); await s.tick(); s.invalidate()
        clock = 2; tv.volume = 12; await s.tick()
        XCTAssertTrue(tv.sets.isEmpty); XCTAssertEqual(d.state.scalar, 0.12)
    }
    @MainActor func testChangingDelayAppliesToPendingTarget() async {
        let d = FakeDevice(), tv = FakeTV(); var clock: TimeInterval = 0
        let s = VolumeSync(device: d, tv: tv, quietInterval: 0.5, now: { clock })
        await s.tick(); d.command(0.3); await s.tick(); clock = 0.4
        s.quietInterval = 1; await s.tick(); XCTAssertTrue(tv.sets.isEmpty)
        s.quietInterval = 0; await s.tick(); XCTAssertEqual(tv.sets, [30])
    }
    @MainActor func testAcknowledgedFallbackHasNoInterStepDelay() async {
        let d = FakeDevice(), tv = FakeTV(); tv.supported = false
        var clock: TimeInterval = 0
        let s = VolumeSync(device: d, tv: tv, quietInterval: 1, now: { clock })
        await s.tick(); d.command(0.23); await s.tick()
        XCTAssertEqual(s.nextTickDelay, 0.1)
        clock = 1; await s.tick()
        XCTAssertEqual(s.nextTickDelay, 0.1)
        await s.tick(); XCTAssertEqual(tv.volume, 21); XCTAssertEqual(s.nextTickDelay, 0.1)
        await s.tick(); await s.tick()
        XCTAssertEqual(tv.steps.count, 3); XCTAssertEqual(tv.volume, 23)
        XCTAssertEqual(s.nextTickDelay, 0.1)
    }
    @MainActor func testDelayedFeedbackDoesNotSendDuplicateKey() async {
        let d = FakeDevice(), tv = FakeTV(); tv.supported = false
        let s = VolumeSync(device: d, tv: tv); await s.tick()
        d.command(0.21); await s.tick()
        tv.onStep = { tv.staleReads = 1 }
        await s.tick()
        XCTAssertEqual(tv.steps, [true]); XCTAssertEqual(tv.volume, 21)
        XCTAssertFalse(s.hasPendingTarget); XCTAssertEqual(d.state.scalar, 0.21)
    }
    @MainActor func testInvalidationDuringMutationCannotRestoreOldTarget() async {
        let d = FakeDevice(), tv = FakeTV()
        let s = VolumeSync(device: d, tv: tv); await s.tick()
        d.command(0.4); let confirmations = d.confirms
        tv.onSet = { s.invalidate() }; await s.tick()
        XCTAssertFalse(s.connected); XCTAssertFalse(s.hasPendingTarget)
        XCTAssertEqual(d.confirms, confirmations)
        tv.volume = 12; await s.tick()
        XCTAssertEqual(d.state.scalar, 0.12); XCTAssertEqual(tv.sets, [40])
    }
    @MainActor func testReversalWhileStepInFlightUsesLatestTarget() async {
        let d = FakeDevice(), tv = FakeTV(); tv.supported = false
        let s = VolumeSync(device: d, tv: tv); await s.tick()
        d.command(0.3); await s.tick()
        tv.onStep = { d.command(0.19) }; await s.tick()
        XCTAssertEqual(d.state.scalar, 0.19)
        await s.tick(); await s.tick()
        XCTAssertEqual(tv.steps, [true, false, false]); XCTAssertEqual(tv.volume, 19)
    }
    func testInvalidRangesAreRejected() {
        XCTAssertThrowsError(try TVVolume(value: 0, maximum: 0))
        XCTAssertThrowsError(try TVVolume(value: 101, maximum: 100))
        XCTAssertThrowsError(try TVVolume(value: -1, maximum: 100))
        XCTAssertEqual(MemoryLayout<DriverState>.size, 16)
    }
}
