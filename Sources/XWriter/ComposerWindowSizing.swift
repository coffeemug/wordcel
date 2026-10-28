import AppKit

enum ComposerWindowSizing {
    static let minimumHeight: CGFloat = 332
    static let maximumHeight: CGFloat = 760
    static let screenMargin: CGFloat = 24

    static func frame(current: NSRect, contentHeight: CGFloat, screen: NSRect) -> NSRect {
        let available = screen.insetBy(dx: 0, dy: screenMargin)
        let maximum = min(maximumHeight, available.height)
        let height = min(maximum, max(minimumHeight, ceil(contentHeight)))
        var result = current
        result.size.height = height
        // Keep the top edge still while typing; move up only if necessary to
        // stay above the Dock. Deleting text shrinks from the bottom as well.
        result.origin.y = max(available.minY, min(current.maxY, available.maxY) - height)
        return result
    }
}
