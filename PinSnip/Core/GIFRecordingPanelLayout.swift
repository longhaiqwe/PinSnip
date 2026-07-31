import CoreGraphics
import Foundation

public enum GIFRecordingPanelLayout {
    public static let usesTitleBar = false
    public static let hidesOnDeactivate = false
    public static let contentSize = CGSize(width: 400, height: 50)
    public static let cornerRadius = ScrollingCapturePanelLayout.cornerRadius
    public static let recordingBorderColor = SelectionOverlayStyle.selectionBorderColor

    public static func progressText(
        elapsedSeconds: Int,
        maximumSeconds: Int
    ) -> String {
        let elapsed = max(0, elapsedSeconds)
        let maximum = max(0, maximumSeconds)
        return String(
            format: "录制中 · %02d:%02d / %02d:%02d",
            elapsed / 60,
            elapsed % 60,
            maximum / 60,
            maximum % 60
        )
    }

    public static func panelFrame(
        visibleFrame: CGRect,
        selectionFrame: CGRect
    ) -> CGRect {
        ScrollingCapturePanelLayout.panelFrame(
            visibleFrame: visibleFrame,
            selectionFrame: selectionFrame,
            size: contentSize
        )
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
