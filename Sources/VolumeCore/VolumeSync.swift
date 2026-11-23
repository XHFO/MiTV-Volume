import Foundation

public struct DriverState: Equatable {
    public var revision: UInt64
    public var scalar: Float
    public var reserved: UInt32 = 0
    public init(revision: UInt64 = 0, scalar: Float = 0) {
        self.revision = revision; self.scalar = scalar
    }
}
public struct TVVolume: Equatable {
    public let value: Int
    public let maximum: Int
    public var scalar: Float { Float(value) / Float(maximum) }
    public init(value: Int, maximum: Int) throws {
        guard maximum > 0, maximum <= 1000, value >= 0, value <= maximum else {
            throw VolumeError("电视返回了无效的音量范围")
        }
        self.value = value; self.maximum = maximum
    }
    public func quantize(_ scalar: Float) -> Int {
        Int((min(1, max(0, scalar)) * Float(maximum)).rounded())
    }
}
public struct VolumeError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
@MainActor public protocol VolumeDevice: AnyObject {
    func read() throws -> DriverState
    // Return false if a newer user command won the race.
    func confirm(_ volume: Float, revision: UInt64) throws -> Bool
}
@MainActor public protocol VolumeTV: AnyObject {
    func read() async throws -> TVVolume
    // false means the model explicitly rejected absolute volume control.
    func setAbsolute(_ value: Int) async throws -> Bool
    func step(up: Bool) async throws
}

/// One serial worker; never enqueue an unbounded series of slider requests.
/// Each iteration reads the latest revision before issuing its one mutation.
@MainActor public final class VolumeSync {
    private let device: VolumeDevice
    private let tv: VolumeTV
    private var primed = false
    private var seen: UInt64 = 0
    private var actual: TVVolume?
    private var target: Int?
    private var stagnant = 0
    private var attempts = 0
    private var absolute = true
    private var busy = false
    private let now: () -> TimeInterval
    private var lastInputAt: TimeInterval = 0
    private var refreshBeforeSend = false
    /// Quiet time after the latest observed slider change; polling itself stays fast.
    public var quietInterval: TimeInterval
    public private(set) var status = "正在连接电视…"
    public private(set) var connected = false
    public var hasPendingTarget: Bool { target != nil }

    public init(device: VolumeDevice, tv: VolumeTV, quietInterval: TimeInterval = 0,
                now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.device = device; self.tv = tv; self.quietInterval = quietInterval; self.now = now
    }
    public func invalidate() { primed = false; target = nil; connected = false }

    public func tick() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let snapshot = try device.read()
            if !primed {
                let value = try await tv.read()
                guard try device.confirm(value.scalar, revision: snapshot.revision) else { return }
                actual = value; seen = snapshot.revision; primed = true
                target = nil; absolute = true
                connected = true; status = "已同步 · \(value.value)/\(value.maximum)"
                return
            }
            if snapshot.revision != seen, let value = actual {
                seen = snapshot.revision
                target = value.quantize(snapshot.scalar)
                stagnant = 0; attempts = 0
                lastInputAt = now(); refreshBeforeSend = true
            }
            let revision = seen
            if target != nil {
                let delay = quietInterval.isFinite ? max(0, quietInterval) : 0
                guard now() - lastInputAt >= delay else {
                    status = "等待调整结束 · 目标 \(target!)/\(actual!.maximum)"
                    return
                }
                if refreshBeforeSend {
                    // A remote or an already-sent command may have changed the TV during the wait.
                    actual = try await tv.read()
                    guard try device.read().revision == revision else { return }
                    refreshBeforeSend = false
                }
            }
            let previous = actual
            if let goal = target, let value = actual, goal != value.value {
                // A read or previous request may have yielded while the user dragged again.
                guard try device.read().revision == revision else { return }
                if absolute {
                    absolute = try await tv.setAbsolute(goal)
                    // Do not send a fallback key after yielding; recheck revision next tick.
                    if !absolute { return }
                } else {
                    try await tv.step(up: goal > value.value)
                }
                attempts += 1
                try await Task.sleep(nanoseconds: 80_000_000)
            }
            let value = try await tv.read()
            actual = value
            guard try device.read().revision == revision else { return }
            if let goal = target {
                if value.value == goal {
                    target = nil
                } else {
                    stagnant = previous?.value == value.value ? stagnant + 1 : 0
                    // Some TVs report success without applying setVolum.
                    if absolute && stagnant >= 3 { absolute = false; stagnant = 0 }
                    else if stagnant >= 3 || attempts >= value.maximum + 10 {
                        target = nil
                        status = "电视未达到目标音量，已回读实际值 · \(value.value)/\(value.maximum)"
                        _ = try device.confirm(value.scalar, revision: revision)
                        connected = true
                        return
                    }
                }
            }
            // Keep the local target stable while stepping toward it. Otherwise the next
            // shortcut press starts from an intermediate TV value and appears to fight back.
            if target == nil {
                guard try device.confirm(value.scalar, revision: revision) else { return }
            }
            connected = true
            status = target == nil ? "已同步 · \(value.value)/\(value.maximum)" : "正在同步 · \(value.value)/\(value.maximum)"
        } catch {
            // Never replay stale commands when a TV wakes or a network reconnects.
            primed = false; target = nil; connected = false
            status = "未同步 · \(error.localizedDescription)"
        }
    }
}
