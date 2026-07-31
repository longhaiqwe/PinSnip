public enum CapturePanelKeyboardAction: Equatable, Sendable {
    case cancel
}

public enum CapturePanelKeyboardShortcut {
    public static let escapeKeyCode: UInt32 = 53

    public static func action(
        keyCode: UInt32
    ) -> CapturePanelKeyboardAction? {
        keyCode == escapeKeyCode ? .cancel : nil
    }
}
