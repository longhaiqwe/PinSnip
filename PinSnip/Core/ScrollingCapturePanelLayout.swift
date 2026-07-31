import CoreGraphics

public enum ScrollingCapturePanelLayout {
    public static let usesTitleBar = false
    public static let contentSize = CGSize(width: 460, height: 50)
    public static let cornerRadius: CGFloat = 14
    public static let selectionSpacing: CGFloat = 12

    public static func progressText(
        isAutomatic: Bool,
        frameCount: Int,
        pixelHeight: Int
    ) -> String {
        let mode = isAutomatic ? "自动滚动" : "手动滚动"
        return "\(mode) · \(frameCount) 屏 · \(pixelHeight) px"
    }

    public static func panelFrame(
        visibleFrame: CGRect,
        selectionFrame: CGRect,
        size: CGSize = contentSize
    ) -> CGRect {
        let selection = selectionFrame.standardized
        let x = min(
            max(
                visibleFrame.minX,
                selection.midX - size.width / 2
            ),
            visibleFrame.maxX - size.width
        )
        let aboveY = selection.maxY + selectionSpacing
        let belowY = selection.minY - size.height - selectionSpacing
        let y: CGFloat
        if aboveY + size.height <= visibleFrame.maxY {
            y = aboveY
        } else if belowY >= visibleFrame.minY {
            y = belowY
        } else {
            y = min(
                max(visibleFrame.minY, aboveY),
                visibleFrame.maxY - size.height
            )
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
