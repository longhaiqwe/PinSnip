import CoreGraphics

public enum PinWindowLayout {
    /// 在可用屏幕中央展开贴图，预留边距，并限制连续贴图的偏移。
    public static func initialFrame(
        imageSize: CGSize,
        visibleFrame: CGRect,
        cascadeIndex: Int
    ) -> CGRect {
        let margin = min(16, min(visibleFrame.width, visibleFrame.height) / 4)
        let available = visibleFrame.insetBy(dx: margin, dy: margin)
        let naturalSize = CGSize(width: max(1, imageSize.width), height: max(1, imageSize.height))
        let scale = min(
            1,
            min(min(560, available.width) / naturalSize.width,
                min(420, available.height) / naturalSize.height)
        )
        let size = CGSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
        let offset = CGFloat(max(0, cascadeIndex) % 8) * 18
        return CGRect(
            x: min(max(available.minX, available.midX - size.width / 2 + offset), available.maxX - size.width),
            y: min(max(available.minY, available.midY - size.height / 2 - offset), available.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }
}
