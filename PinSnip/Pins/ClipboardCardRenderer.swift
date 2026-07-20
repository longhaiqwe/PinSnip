import AppKit
import PinSnipCore

@MainActor
enum ClipboardCardRenderer {
    static func image(for payload: ClipboardPayload) -> CGImage? {
        switch payload {
        case let .imageData(data):
            return NSImage(data: data)?.pinSnipCGImage
        case let .file(url):
            return NSImage(contentsOf: url)?.pinSnipCGImage
        case let .text(text):
            return textCard(text).pinSnipCGImage
        case let .color(color):
            return colorCard(color).pinSnipCGImage
        }
    }

    private static func textCard(_ text: String) -> NSImage {
        let width: CGFloat = 460
        let padding: CGFloat = 28
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.95, alpha: 1)
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textBounds = attributed.boundingRect(
            with: NSSize(width: width - padding * 2, height: 640),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let height = min(700, max(120, ceil(textBounds.height) + padding * 2))
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor(calibratedRed: 0.075, green: 0.09, blue: 0.12, alpha: 0.98).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: image.size), xRadius: 18, yRadius: 18).fill()
        attributed.draw(
            with: NSRect(x: padding, y: padding, width: width - padding * 2, height: height - padding * 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        image.unlockFocus()
        return image
    }

    private static func colorCard(_ color: RGBAColor) -> NSImage {
        let size = NSSize(width: 360, height: 220)
        let image = NSImage(size: size)
        let nsColor = NSColor(
            srgbRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
        let luminance = color.red * 0.2126 + color.green * 0.7152 + color.blue * 0.0722
        let foreground = luminance > 0.58 ? NSColor.black : NSColor.white
        let red = Int(round(color.red * 255))
        let green = Int(round(color.green * 255))
        let blue = Int(round(color.blue * 255))
        let hex = String(format: "#%02X%02X%02X", red, green, blue)

        image.lockFocus()
        nsColor.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 18, yRadius: 18).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let hexAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 32, weight: .semibold),
            .foregroundColor: foreground,
            .paragraphStyle: paragraph
        ]
        let rgbAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium),
            .foregroundColor: foreground.withAlphaComponent(0.76),
            .paragraphStyle: paragraph
        ]
        hex.draw(in: NSRect(x: 20, y: 112, width: 320, height: 44), withAttributes: hexAttributes)
        "RGB \(red) · \(green) · \(blue)".draw(
            in: NSRect(x: 20, y: 76, width: 320, height: 26),
            withAttributes: rgbAttributes
        )
        image.unlockFocus()
        return image
    }
}

private extension NSImage {
    var pinSnipCGImage: CGImage? {
        var rect = NSRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

