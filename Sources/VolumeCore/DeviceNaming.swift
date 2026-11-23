import Foundation

public enum DeviceNaming {
    public static func validatedCustomName(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count <= 80, name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw VolumeError("设备名称请使用 80 字以内的单行文字")
        }
        return name
    }
    public static func resolved(custom: String, outputName: String) -> String {
        custom.isEmpty ? "\(outputName)（音量控制）" : custom
    }
}
