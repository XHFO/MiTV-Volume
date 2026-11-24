import AppKit
@main struct MenuIconTests {
    static func main() {
        // Only distinct, actually observed system appearances are offered.
        assert(DeviceIconStyle.selectable.map(\.rawValue) == [0, 1, 2, 4, 7, 8, 11])
        for current in DeviceIconStyle.allCases {
            let choices = DeviceIconStyle.menuChoices(retaining: current)
            assert(choices.contains(current))
            assert(Set(choices.map(\.rawValue)).count == choices.count)
            assert(choices.count == (DeviceIconStyle.selectable.contains(current) ? 7 : 8))
            assert(current.image != nil, "Missing menu preview for \(current.title)")
        }
        assert(DeviceIconStyle(rawValue: 12) == nil)
        print("Menu icons passed: seven distinct choices; legacy selection retained without reset; all previews available.")
    }
}
