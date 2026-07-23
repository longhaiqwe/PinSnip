import CoreGraphics

public enum CaptureOverlayPresentationPolicy {
    public static let hidesOnDeactivate = false
    public static let preservesFrontmostApplication = true
    public static let animatesPresentation = false

    public static func dimmingOpacity(hasSelection: Bool) -> CGFloat {
        hasSelection ? 0.38 : 0
    }
}
