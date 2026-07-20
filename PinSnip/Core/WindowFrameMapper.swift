import CoreGraphics

public enum WindowFrameMapper {
    public static func localFrame(
        quartzFrame: CGRect,
        primaryScreenMaxY: CGFloat,
        screenFrame: CGRect
    ) -> CGRect? {
        let appKitFrame = CGRect(
            x: quartzFrame.minX,
            y: primaryScreenMaxY - quartzFrame.maxY,
            width: quartzFrame.width,
            height: quartzFrame.height
        )
        let visibleFrame = appKitFrame.intersection(screenFrame)
        guard !visibleFrame.isNull, !visibleFrame.isEmpty else { return nil }

        return visibleFrame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }
}
