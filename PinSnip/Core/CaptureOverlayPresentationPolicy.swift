import CoreGraphics

public enum CaptureOverlayPresentationPolicy {
    public static let hidesOnDeactivate = false

    public static func dimmingOpacity(hasSelection: Bool) -> CGFloat {
        hasSelection ? 0.38 : 0
    }
}
