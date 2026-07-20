import Foundation

public enum ClipboardPayload: Equatable, Sendable {
    case imageData(Data)
    case file(URL)
    case text(String)
    case color(RGBAColor)

    public static func classify(text: String) -> ClipboardPayload {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let color = RGBAColor(hex: candidate) {
            return .color(color)
        }
        return .text(text)
    }
}
