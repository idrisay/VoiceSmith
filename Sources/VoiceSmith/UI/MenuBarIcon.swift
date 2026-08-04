import AppKit

/// The menu bar glyph, drawn rather than taken from SF Symbols so the silhouette
/// is distinctive at 18pt and reads the same in light and dark menu bars.
///
/// Every variant is a *template* image: macOS recolours it for the current menu
/// bar appearance, including the inverted look while the menu is open. The only
/// exception is the recording state, which paints its own red so it's obvious at
/// a glance that a mic is live.
enum MenuBarIcon {

    enum State {
        case idle
        case recording
        case working
        case problem
    }

    static func image(for state: State) -> NSImage {
        switch state {
        case .idle: return template { drawMic(filled: false) }
        case .recording: return recordingImage()
        case .working: return template { drawWaveform() }
        case .problem: return template { drawMic(filled: false); drawSlash() }
        }
    }

    // MARK: - Canvas

    private static let size = NSSize(width: 18, height: 18)

    private static func template(_ draw: @escaping () -> Void) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.set()
            draw()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Non-template so the red survives. Menu bar tinting would otherwise flatten it.
    private static func recordingImage() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.systemRed.set()
            drawMic(filled: true)
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Shapes

    /// A microphone: capsule head, a yoke arc cradling it, and a short stand.
    private static func drawMic(filled: Bool) {
        let line: CGFloat = 1.4

        let head = NSBezierPath(
            roundedRect: NSRect(x: 6.6, y: 7.0, width: 4.8, height: 8.4),
            xRadius: 2.4,
            yRadius: 2.4
        )
        if filled {
            head.fill()
        } else {
            head.lineWidth = line
            head.stroke()
        }

        // Yoke — a half circle opening upward, drawn under the head.
        let yoke = NSBezierPath()
        yoke.appendArc(
            withCenter: NSPoint(x: 9, y: 8.2),
            radius: 4.6,
            startAngle: 200,
            endAngle: 340,
            clockwise: false
        )
        yoke.lineWidth = line
        yoke.lineCapStyle = .round
        yoke.stroke()

        // Stand.
        let stand = NSBezierPath()
        stand.move(to: NSPoint(x: 9, y: 3.6))
        stand.line(to: NSPoint(x: 9, y: 1.9))
        stand.lineWidth = line
        stand.lineCapStyle = .round
        stand.stroke()
    }

    /// Bars, for the transcribing/improving phase — the mic is no longer listening.
    private static func drawWaveform() {
        let heights: [CGFloat] = [4, 8, 12, 8, 4]
        let width: CGFloat = 1.5
        let gap: CGFloat = 1.6
        let total = CGFloat(heights.count) * width + CGFloat(heights.count - 1) * gap
        var x = (size.width - total) / 2

        for height in heights {
            let bar = NSBezierPath(
                roundedRect: NSRect(x: x, y: (size.height - height) / 2, width: width, height: height),
                xRadius: width / 2,
                yRadius: width / 2
            )
            bar.fill()
            x += width + gap
        }
    }

    private static func drawSlash() {
        let slash = NSBezierPath()
        slash.move(to: NSPoint(x: 4.0, y: 3.4))
        slash.line(to: NSPoint(x: 14.0, y: 14.6))
        slash.lineCapStyle = .round

        // Knock a clear channel out from under the slash so it reads as one
        // stroke crossing the mic, rather than tangling with the outline.
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        let channel = slash.copy() as! NSBezierPath
        channel.lineWidth = 3.0
        channel.lineCapStyle = .round
        channel.stroke()

        NSGraphicsContext.current?.compositingOperation = .sourceOver
        slash.lineWidth = 1.5
        slash.stroke()
    }
}
