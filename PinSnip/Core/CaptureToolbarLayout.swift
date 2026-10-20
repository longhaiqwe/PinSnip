import Foundation

public enum CaptureToolbarAction: Int, Equatable, Sendable {
    case copy = 20
    case save = 21
    case pin = 22
    case recordGIF = 23
    case scrollCapture = 24
    case cancel = 99
}

public enum CaptureToolbarStyle {
    public static let controlSize: CGFloat = 32
    public static let controlRadius: CGFloat = 6
    public static let itemSpacing: CGFloat = 4
    public static let groupSpacing: CGFloat = 10
    public static let screenInset: CGFloat = 10
    public static let backgroundColor = RGBAColor(
        red: 0.90,
        green: 0.90,
        blue: 0.90
    )
    public static let usesLightControls = true
}

public enum CaptureToolbarLayout {
    /// AppKit coordinates: first try outside the selection, then clamp within the screen.
    public static func frame(size: CGSize, beside anchor: CGRect, in bounds: CGRect,
                             preferredCenterX: CGFloat? = nil, prefersBelow: Bool = true) -> CGRect {
        let safe = bounds.insetBy(dx: CaptureToolbarStyle.screenInset, dy: CaptureToolbarStyle.screenInset)
        let gap = CaptureToolbarStyle.groupSpacing
        let below = anchor.minY - gap - size.height
        let above = anchor.maxY + gap
        let preferred = prefersBelow ? below : above
        let alternate = prefersBelow ? above : below
        let fits: (CGFloat) -> Bool = { $0 >= safe.minY && $0 + size.height <= safe.maxY }
        let y = fits(preferred) ? preferred : (fits(alternate) ? alternate : min(max(preferred, safe.minY), safe.maxY - size.height))
        let x = preferredCenterX.map { $0 - size.width / 2 } ?? (anchor.maxX - size.width)
        return CGRect(x: max(safe.minX, min(x, safe.maxX - size.width)), y: max(safe.minY, y),
                      width: size.width, height: size.height)
    }

    public static let stillImageTrailingActions: [CaptureToolbarAction] = [
        .scrollCapture,
        .save,
        .pin,
        .cancel,
        .copy,
    ]

    public static let animatedGIFActions: [CaptureToolbarAction] = [
        .cancel,
        .recordGIF,
    ]

    public static let scrollingCaptureActions: [CaptureToolbarAction] = [
        .cancel,
        .scrollCapture,
    ]
}
