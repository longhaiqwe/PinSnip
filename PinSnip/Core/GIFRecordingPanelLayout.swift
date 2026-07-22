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
