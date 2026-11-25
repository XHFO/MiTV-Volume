import AppKit
@main struct MenuIconTests {
    static func main() {
        // Only the five requested appearances are offered.
        assert(DeviceIconStyle.selectable.map(\.rawValue) == [0, 1, 2, 4, 11])
        for current in DeviceIconStyle.allCases {
            let choices = DeviceIconStyle.menuChoices(retaining: current)
            assert(choices.contains(current))
            assert(Set(choices.map(\.rawValue)).count == choices.count)
            assert(choices.count == (DeviceIconStyle.selectable.contains(current) ? 5 : 6))
            assert(current.image != nil, "Missing menu preview for \(current.title)")
        }
        assert(DeviceIconStyle(rawValue: 12) == nil)
        print("Menu icons passed: five choices; legacy selection retained without reset; all previews available.")
    }
}
