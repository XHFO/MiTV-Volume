import Foundation
import CoreAudio
import VolumeCore

@MainActor final class ProxyDevice: VolumeDevice {
    static let uid = "MiTVVolumeDevice_UID"
    static let selector: AudioObjectPropertySelector = 0x6d747673 // mtvs
    struct Output { let id: AudioObjectID; let uid: String; let name: String }
    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func check(_ code: OSStatus) throws {
        if code != noErr { throw VolumeError("音频设备错误（\(code)）") }
    }
    static func lookup(_ uid: String, box: Bool = false) throws -> AudioObjectID {
        var addr = address(box ? kAudioHardwarePropertyTranslateUIDToBox : kAudioHardwarePropertyTranslateUIDToDevice)
        let string = uid as CFString
        var value = Unmanaged.passUnretained(string)
        defer { withExtendedLifetime(string) {} }
        var result: AudioObjectID = 0
        var size = UInt32(MemoryLayout.size(ofValue: result))
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
            UInt32(MemoryLayout.size(ofValue: value)), &value, &size, &result))
        guard result != 0 else { throw VolumeError(box || uid == Self.uid ? "系统音量控制尚未就绪，请在连接设置中点击“启用音量控制”" : "所选输出设备未连接") }
        return result
    }
    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var addr = address(selector)
        var result: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: result))
        try check(AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &result))
        guard let result else { throw VolumeError("音频设备名称不可用") }
        return result.takeRetainedValue() as String
    }
    static func outputs() throws -> [Output] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size))
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids))
        return ids.compactMap { id in
            var stream = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &stream, 0, nil, &bytes) == noErr, bytes > 0,
                  let uid = try? string(id, kAudioDevicePropertyDeviceUID), uid != Self.uid,
                  let name = try? string(id, kAudioObjectPropertyName) else { return nil }
            return Output(id: id, uid: uid, name: name)
        }
    }
    func read() throws -> DriverState {
        let id = try Self.lookup(Self.uid)
        var addr = Self.address(Self.selector)
        var object: Unmanaged<CFData>?
        var size = UInt32(MemoryLayout.size(ofValue: object))
        try Self.check(AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &object))
        guard let object else { throw VolumeError("系统音量控制响应为空") }
        let data = object.takeRetainedValue()
        guard CFGetTypeID(data) == CFDataGetTypeID(), CFDataGetLength(data) == 16 else {
            throw VolumeError("系统音量控制版本不匹配，请重新启用")
        }
        var result = DriverState()
        withUnsafeMutableBytes(of: &result) { bytes in
            CFDataGetBytes(data, CFRange(location: 0, length: 16), bytes.baseAddress!.assumingMemoryBound(to: UInt8.self))
        }
        guard result.scalar.isFinite else { throw VolumeError("系统音量数值无效") }
        return result
    }
    func confirm(_ volume: Float, revision: UInt64) throws -> Bool {
        let id = try Self.lookup(Self.uid)
        var addr = Self.address(Self.selector)
        var state = DriverState(revision: revision, scalar: volume)
        let data = withUnsafeBytes(of: &state) { bytes in
            CFDataCreate(nil, bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), 16)!
        }
        var object = Unmanaged.passUnretained(data)
        defer { withExtendedLifetime(data) {} }
        let code = AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout.size(ofValue: object)), &object)
        if code == kAudioHardwareIllegalOperationError { return false }
        try Self.check(code)
        return true
    }
    static func configure(outputUID: String) throws {
        _ = try lookup(outputUID)
        let box = try lookup("MiTVVolumeBox_UID", box: true)
        var identify = address(kAudioObjectPropertyIdentify)
        var pid = getpid()
        try check(AudioObjectSetPropertyData(box, &identify, 0, nil, 4, &pid))
        try boxCommand("outputDevice=\(outputUID)", box: box)
        try boxCommand("outputDeviceHideWhenUnavailable=1", box: box)
    }
    static var supportsDeviceIcons: Bool {
        guard let box = try? lookup("MiTVVolumeBox_UID", box: true),
              let version = try? string(box, kAudioObjectPropertyFirmwareVersion) else { return false }
        return version == "0.3.6"
    }
    static func setIcon(_ style: DeviceIconStyle) throws {
        guard supportsDeviceIcons else { throw VolumeError("图标选择已保存。点击“启用音量控制”更新内置音频组件后生效。") }
        let box = try lookup("MiTVVolumeBox_UID", box: true)
        var identify = address(kAudioObjectPropertyIdentify)
        var pid = getpid()
        try check(AudioObjectSetPropertyData(box, &identify, 0, nil, 4, &pid))
        try boxCommand("deviceIconStyle=\(style.rawValue)", box: box)
    }
    static func setName(_ name: String) throws {
        let box = try lookup("MiTVVolumeBox_UID", box: true)
        var identify = address(kAudioObjectPropertyIdentify)
        var pid = getpid()
        try check(AudioObjectSetPropertyData(box, &identify, 0, nil, 4, &pid))
        try boxCommand("deviceName=\(name)", box: box)
    }
    private static func boxCommand(_ value: String, box: AudioObjectID) throws {
        var name = address(kAudioObjectPropertyName)
        let string = value as CFString
        var command = Unmanaged.passUnretained(string)
        defer { withExtendedLifetime(string) {} }
        try check(AudioObjectSetPropertyData(box, &name, 0, nil,
            UInt32(MemoryLayout.size(ofValue: command)), &command))
    }
    static func isConnected(_ uid: String) -> Bool {
        guard let id = try? lookup(uid) else { return false }
        return (try? integer(id, kAudioDevicePropertyDeviceIsAlive)) == 1
    }
    static func integer(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> UInt32 {
        var addr = address(selector); var value: UInt32 = 0; var size: UInt32 = 4
        try check(AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value))
        return value
    }
    static var currentOutputUID: String? {
        guard let id = try? defaultOutput() else { return nil }
        return try? string(id, kAudioDevicePropertyDeviceUID)
    }
    static func useFallback(preferredUID: String?) throws -> String? {
        if let uid = preferredUID {
            guard uid != Self.uid, isConnected(uid) else { return nil }
            if currentOutputUID != uid { try makeDefault(uid) }
            return uid
        }
        guard let device = try outputs().first(where: {
            (try? integer($0.id, kAudioDevicePropertyTransportType)) == kAudioDeviceTransportTypeBuiltIn
        }) else { return nil }
        if currentOutputUID != device.uid { try makeDefault(device.uid) }
        return device.uid
    }
    static func defaultOutput() throws -> AudioObjectID {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id: AudioObjectID = 0; var size: UInt32 = 4
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id))
        return id
    }
    static func makeDefault(_ uid: String) throws {
        var id = try lookup(uid)
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        try check(AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, 4, &id))
    }
}
