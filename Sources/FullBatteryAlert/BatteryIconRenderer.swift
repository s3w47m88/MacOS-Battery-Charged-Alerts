import AppKit

/// Renders a menu bar battery icon that matches the native macOS look but with
/// a thinner outline and optional percent text inside the fill bar.
enum BatteryIconRenderer {
    /// Width × height of the icon in points. Slightly wider than the native one
    /// to fit a 2- or 3-digit percent label.
    private static let bodySize = NSSize(width: 25, height: 12)
    private static let capWidth: CGFloat = 1.5
    private static let totalSize = NSSize(width: 26.5, height: 12)
    private static let stroke: CGFloat = 1.0   // ~1pt thinner than SF Symbol default
    private static let innerInset: CGFloat = 1.5

    static func render(percentage pct: Int, isCharging: Bool, isPluggedIn: Bool, showPercentage: Bool) -> NSImage {
        let percentage = max(0, min(100, pct))
        let image = NSImage(size: totalSize, flipped: false) { _ in
            drawBatteryShape()
            if isCharging || isPluggedIn {
                drawFillWithBolt(percentage: percentage)
            } else if showPercentage {
                drawFillWithPercent(percentage: percentage)
            } else {
                drawFill(percentage: percentage)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawBatteryShape() {
        let bodyRect = NSRect(
            x: stroke / 2,
            y: stroke / 2,
            width: bodySize.width - stroke,
            height: bodySize.height - stroke
        )
        NSColor.black.setStroke()
        let path = NSBezierPath(roundedRect: bodyRect, xRadius: 3, yRadius: 3)
        path.lineWidth = stroke
        path.stroke()

        // Battery cap on the right edge
        let capRect = NSRect(
            x: bodySize.width - 0.25,
            y: bodySize.height / 2 - 2.5,
            width: capWidth,
            height: 5
        )
        NSColor.black.setFill()
        NSBezierPath(roundedRect: capRect, xRadius: 0.75, yRadius: 0.75).fill()
    }

    private static func drawFill(percentage: Int) {
        let interior = NSRect(
            x: stroke / 2 + innerInset,
            y: stroke / 2 + innerInset,
            width: bodySize.width - stroke - innerInset * 2,
            height: bodySize.height - stroke - innerInset * 2
        )
        let pct = max(0, min(100, percentage))
        guard pct > 0 else { return }
        let fillWidth = interior.width * CGFloat(pct) / 100.0
        let fillRect = NSRect(
            x: interior.minX,
            y: interior.minY,
            width: fillWidth,
            height: interior.height
        )
        NSColor.black.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5).fill()
    }

    private static func drawFillWithBolt(percentage: Int) {
        // Same trick as drawFillWithPercent: draw the bolt as solid black, then
        // XOR a black fill rect on top so within the charged region the bolt
        // becomes transparent (reading as menu-bar color against the black
        // fill) while outside the fill it stays solid black.
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .black)
        guard let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let boltOrigin = NSPoint(
            x: (bodySize.width - bolt.size.width) / 2.0,
            y: (bodySize.height - bolt.size.height) / 2.0
        )
        bolt.draw(at: boltOrigin, from: NSRect(origin: .zero, size: bolt.size),
                  operation: .sourceOver, fraction: 1.0)

        let pct = max(0, min(100, percentage))
        guard pct > 0 else { return }
        let interior = NSRect(
            x: stroke / 2 + innerInset,
            y: stroke / 2 + innerInset,
            width: bodySize.width - stroke - innerInset * 2,
            height: bodySize.height - stroke - innerInset * 2
        )
        let fillWidth = interior.width * CGFloat(pct) / 100.0
        let fillRect = NSRect(
            x: interior.minX,
            y: interior.minY,
            width: fillWidth,
            height: interior.height
        )
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        ctx.compositingOperation = .xor
        NSColor.black.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5).fill()
        ctx.restoreGraphicsState()
    }

    private static func drawFillWithPercent(percentage: Int) {
        // Draw digits as solid black across the interior, then XOR a black
        // fill rectangle on top so that within the filled (charged) region the
        // alpha is inverted: digits become transparent and the background
        // becomes opaque. Outside the fill, the digits remain solid black.
        // Net effect: digits are visible on both sides of the charge line and
        // appear inverted on the charged side.
        let font = NSFont.systemFont(ofSize: 8, weight: .heavy)
        let text = "\(percentage)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = str.size()
        let textOrigin = NSPoint(
            x: (bodySize.width - textSize.width) / 2.0,
            y: (bodySize.height - textSize.height) / 2.0
        )
        str.draw(at: textOrigin)

        let pct = max(0, min(100, percentage))
        guard pct > 0 else { return }
        let interior = NSRect(
            x: stroke / 2 + innerInset,
            y: stroke / 2 + innerInset,
            width: bodySize.width - stroke - innerInset * 2,
            height: bodySize.height - stroke - innerInset * 2
        )
        let fillWidth = interior.width * CGFloat(pct) / 100.0
        let fillRect = NSRect(
            x: interior.minX,
            y: interior.minY,
            width: fillWidth,
            height: interior.height
        )
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        ctx.compositingOperation = .xor
        NSColor.black.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5).fill()
        ctx.restoreGraphicsState()
    }
}
