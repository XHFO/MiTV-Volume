import AppKit

/// Stable values are persisted by the HAL. Append styles; never reorder them.
enum DeviceIconStyle: Int, CaseIterable {
    case display, speaker, headphones, homepod, appleTV, homepodMini
    case usb, bluetooth, airplay, thunderbolt, firewire, builtInMac
    /// Distinct icons visually verified in Control Center. Other persisted IDs
    /// remain readable for compatibility, but aren't offered as new choices.
    static let selectable: [Self] = [.display, .speaker, .headphones, .appleTV, .bluetooth, .airplay, .builtInMac]
    static func menuChoices(retaining current: Self) -> [Self] {
        selectable.contains(current) ? selectable : selectable + [current]
    }
    var title: String {
        ["显示器", "扬声器", "耳机", "HomePod", "电视", "HomePod mini",
         "USB", "蓝牙", "AirPlay", "Thunderbolt", "FireWire", "本机 Mac"][rawValue]
    }
    var menuTitle: String {
        switch self {
        case .homepod, .homepodMini, .usb, .thunderbolt, .firewire:
            return "\(title)（控制中心显示扬声器）"
        default: return title
        }
    }
    var systemHint: String {
        switch self {
        case .homepod, .homepodMini, .usb, .thunderbolt, .firewire:
            return "资源图标已保存；控制中心使用扬声器图标"
        case .appleTV: return "已切换为电视分类；控制中心采用系统电视图标"
        case .builtInMac: return "已切换为本机 Mac 分类；图标由当前 Mac 机型决定"
        default: return "已更新设备分类；重新展开声音面板可查看"
        }
    }
    var symbol: String {
        ["display", "speaker.wave.2.fill", "headphones", "homepod.fill", "tv", "homepodmini.fill",
         "cable.connector", "antenna.radiowaves.left.and.right", "airplayaudio", "bolt.fill", "externaldrive", "laptopcomputer"][rawValue]
    }
    var image: NSImage? {
        // Some Control Center category symbols aren't public SF Symbols.
        // These menu previews do not determine the system's category artwork.
        let image = self == .bluetooth ? NSImage(named: NSImage.Name("NSBluetoothTemplate")) :
            NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        image?.size = NSSize(width: 18, height: 18)
        return image
    }
}
