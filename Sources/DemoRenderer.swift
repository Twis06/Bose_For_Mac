import AppKit

/// Reproducible documentation previews from the app's real NSMenu and slider
/// views. These are rendered demos, explicitly labeled in the public images;
/// no desktop capture, real device IDs, Bluetooth or settings writes are used.
enum DemoRenderer {
    static func export(menu: NSMenu, to path: String) throws {
        let destination = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            guard let appearance = NSAppearance(named: appearance) else { continue }
            var caught: Error?
            appearance.performAsCurrentDrawingAppearance {
                do {
                    try png(menuImage(menu, dark: theme == "dark"), at: destination.appendingPathComponent("menu-\(theme).png"))
                    if let eq = menu.items.first(where: { $0.title.hasPrefix("Equalizer") })?.submenu {
                        try png(menuImage(eq, dark: theme == "dark"), at: destination.appendingPathComponent("equalizer-\(theme).png"))
                    }
                    try png(statusStrip(dark: theme == "dark"), at: destination.appendingPathComponent("battery-\(theme).png"))
                } catch { caught = error }
            }
            if let caught { throw caught }
        }
    }

    private static func menuImage(_ menu: NSMenu, dark: Bool) -> NSImage {
        let width: CGFloat = menu.items.contains(where: { $0.view != nil }) ? 326 : 288
        let heights = menu.items.map { $0.isSeparatorItem ? CGFloat(11) : ($0.view?.frame.height ?? 26) }
        let height = heights.reduce(16, +)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        let background = dark ? NSColor(calibratedWhite: 0.16, alpha: 1) : NSColor(calibratedWhite: 0.97, alpha: 1)
        background.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height), xRadius: 10, yRadius: 10).fill()
        var y = height - 8
        for (index, item) in menu.items.enumerated() {
            let rowHeight = heights[index]
            y -= rowHeight
            if item.isSeparatorItem {
                NSColor.separatorColor.setFill()
                NSRect(x: 12, y: y + 5, width: width - 24, height: 0.5).fill()
                continue
            }
            if let view = item.view {
                // Render the same NSSlider views used in the live menu.
                let backing = DemoBackingView(frame: view.bounds)
                backing.color = background
                backing.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                view.appearance = backing.appearance
                backing.addSubview(view)
                backing.layoutSubtreeIfNeeded()
                if let bitmap = backing.bitmapImageRepForCachingDisplay(in: backing.bounds) {
                    backing.cacheDisplay(in: backing.bounds, to: bitmap)
                    bitmap.draw(in: NSRect(x: (width - view.frame.width) / 2, y: y, width: view.frame.width, height: view.frame.height))
                }
                continue
            }
            let color: NSColor = item.isEnabled || item.attributedTitle != nil ? .labelColor : .secondaryLabelColor
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: color]
            let string = item.attributedTitle ?? NSAttributedString(string: item.title, attributes: attributes)
            string.draw(at: NSPoint(x: 26, y: y + (rowHeight - string.size().height) / 2))
            if item.state == .on {
                NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(paletteColors: [.labelColor]))?
                    .draw(in: NSRect(x: 8, y: y + 7, width: 12, height: 12))
            }
            if item.submenu != nil {
                NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?.draw(in: NSRect(x: width - 20, y: y + 8, width: 9, height: 10))
            }
        }
        image.unlockFocus()
        return image
    }

    private static func statusStrip(dark: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 880, height: 192))
        image.lockFocus()
        let scale = NSAffineTransform()
        scale.scale(by: 4)
        scale.concat()
        (dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor(calibratedWhite: 0.95, alpha: 1)).setFill()
        NSRect(x: 0, y: 0, width: 220, height: 48).fill()
        for (i, value) in [100, 60, 15].enumerated() {
            let x = CGFloat(i) * 72 + 14
            let icon = StatusIcon.image(battery: value, showBattery: true)
            let tinted = NSImage(size: NSSize(width: 112, height: 72))
            tinted.lockFocus()
            icon.draw(in: NSRect(x: 0, y: 0, width: 112, height: 72))
            if dark { NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 112, height: 72).fill(using: .sourceAtop) }
            tinted.unlockFocus()
            tinted.draw(in: NSRect(x: x, y: 22, width: 28, height: 18))
            let label = NSAttributedString(string: "\(value)%", attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor])
            label.draw(at: NSPoint(x: x, y: 5))
        }
        image.unlockFocus()
        return image
    }

    private static func png(_ image: NSImage, at url: URL) throws {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { throw BoseError.message("Couldn’t encode preview.") }
        try data.write(to: url)
    }
}

private final class DemoBackingView: NSView {
    var color = NSColor.windowBackgroundColor
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) { color.setFill(); dirtyRect.fill() }
}
