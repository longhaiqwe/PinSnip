public enum CaptureToolbarAction: Int, Equatable, Sendable {
    case copy = 20
    case save = 21
    case pin = 22
    case recordGIF = 23
    case cancel = 99
}

public enum CaptureToolbarStyle {
    public static let backgroundColor = RGBAColor(
        red: 0.90,
        green: 0.90,
        blue: 0.90
    )
    public static let usesLightControls = true
}

public enum CaptureToolbarLayout {
    public static let stillImageTrailingActions: [CaptureToolbarAction] = [
        .save,
        .pin,
        .cancel,
        .copy,
    ]

    public static let animatedGIFActions: [CaptureToolbarAction] = [
        .cancel,
        .recordGIF,
    ]
}
