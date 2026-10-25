import AppKit

/// A template image so macOS supplies the correct menu-bar foreground color.
enum StatusIcon {
    static func image(battery: Int?, showBattery: Bool) -> NSImage {
        let width: CGFloat = showBattery ? 28 : 18
        let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { rect in
            NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)?
                .draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            if showBattery {
                let track = NSRect(x: 23, y: 2, width: 4, height: 14)
                NSColor.black.withAlphaComponent(0.25).setFill()
                NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
                if let battery {
                    let fraction = CGFloat(max(0, min(100, battery))) / 100
                    if fraction > 0 {
                        NSColor.black.setFill()
                        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width,
                                                       height: max(1, track.height * fraction)), xRadius: 2, yRadius: 2).fill()
                    }
                } else {
                    NSColor.black.withAlphaComponent(0.6).setFill()
                    NSRect(x: 23, y: 8, width: 4, height: 1).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = battery.map { "Bose headphones, battery \($0) percent" } ?? "Bose headphones, battery unavailable"
        return image
    }
}
