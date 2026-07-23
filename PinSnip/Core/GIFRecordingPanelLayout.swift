import CoreGraphics

public enum GIFRecordingPanelLayout {
    public static let hidesOnDeactivate = false
    public static let recordingBorderColor = SelectionOverlayStyle.selectionBorderColor

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
    public let captureRect: CGRect
    public let borderRect: CGRect

    public init(screenFrame: CGRect, selectionRect: CGRect, lineWidth: CGFloat) {
        let selection = selectionRect.standardized
        let width = max(1, lineWidth)
        windowFrame = selection
            .insetBy(dx: -width, dy: -width)
            .offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
        captureRect = CGRect(
            x: width,
            y: width,
            width: selection.width,
            height: selection.height
        )
        borderRect = captureRect.insetBy(dx: -width / 2, dy: -width / 2)
    }
}
