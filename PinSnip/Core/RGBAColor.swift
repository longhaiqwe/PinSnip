import CoreGraphics
import Foundation

public struct RGBAColor: Equatable, Sendable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static let white = RGBAColor(red: 1, green: 1, blue: 1)

    public init?(hex: String) {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let hexadecimalDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard [3, 6, 8].contains(value.count),
              value.unicodeScalars.allSatisfy({ hexadecimalDigits.contains($0) })
        else { return nil }

        let expanded: String
        if value.count == 3 {
            expanded = value.map { "\($0)\($0)" }.joined()
        } else {
            expanded = value
        }

        guard let number = UInt64(expanded, radix: 16) else { return nil }
        if expanded.count == 8 {
            self.init(
                red: CGFloat((number >> 24) & 0xff) / 255,
                green: CGFloat((number >> 16) & 0xff) / 255,
                blue: CGFloat((number >> 8) & 0xff) / 255,
                alpha: CGFloat(number & 0xff) / 255
            )
        } else {
            self.init(
                red: CGFloat((number >> 16) & 0xff) / 255,
                green: CGFloat((number >> 8) & 0xff) / 255,
                blue: CGFloat(number & 0xff) / 255
            )
        }
    }
}
