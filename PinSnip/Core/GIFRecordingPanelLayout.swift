import CoreGraphics

public enum GIFRecordingPanelLayout {
    public static func minimumContentWidth(
        statusWidth: CGFloat,
        stopButtonWidth: CGFloat,
        spacing: CGFloat,
        horizontalPadding: CGFloat
    ) -> CGFloat {
        ceil(statusWidth + stopButtonWidth + spacing + horizontalPadding * 2)
    }
}

public struct GIFRecordingBorderLayout: Equatable, Sendable {
    public let windowFrame: CGRect
    public let borderRect: CGRect

    public init(screenFrame: CGRect, selectionRect: CGRect, lineWidth: CGFloat) {
        let selection = selectionRect.standardized
        let width = max(1, lineWidth)
        windowFrame = selection.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
        borderRect = CGRect(origin: .zero, size: selection.size)
            .insetBy(dx: width / 2, dy: width / 2)
    }
}
