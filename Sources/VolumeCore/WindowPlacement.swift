import Foundation
import CoreGraphics

/// Pure layout helpers for moving windows between displays.
public enum WindowPlacement {
    /// Map a window frame from one screen to another, keeping relative origin and clamping on-screen.
    public static func relocatedFrame(window: CGRect, from fromScreen: CGRect, to toScreen: CGRect) -> CGRect {
        guard fromScreen.width > 1, fromScreen.height > 1, toScreen.width > 1, toScreen.height > 1 else {
            return CGRect(x: toScreen.minX + 40, y: toScreen.minY + 40,
                          width: min(window.width, toScreen.width - 80),
                          height: min(window.height, toScreen.height - 80))
        }
        let relX = (window.minX - fromScreen.minX) / fromScreen.width
        let relY = (window.minY - fromScreen.minY) / fromScreen.height
        var width = min(window.width, toScreen.width - 40)
        var height = min(window.height, toScreen.height - 40)
        width = max(200, width)
        height = max(120, height)
        var x = toScreen.minX + relX * toScreen.width
        var y = toScreen.minY + relY * toScreen.height
        x = min(max(x, toScreen.minX), toScreen.maxX - width)
        y = min(max(y, toScreen.minY), toScreen.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// True when the window's center lies on the candidate screen.
    public static func window(_ window: CGRect, isPrimarilyOn screen: CGRect) -> Bool {
        screen.contains(CGPoint(x: window.midX, y: window.midY))
    }

    /// Full-screen-like: covers most of the screen.
    public static func looksFullScreen(window: CGRect, screen: CGRect) -> Bool {
        guard screen.width > 1, screen.height > 1 else { return false }
        let coverage = (window.width * window.height) / (screen.width * screen.height)
        let inset = window.insetBy(dx: -8, dy: -8)
        return coverage >= 0.92 && inset.contains(screen)
    }
}
