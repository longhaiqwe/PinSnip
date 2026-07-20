public enum PinKeyboardShortcut {
    public static func shouldClose(character: Character, commandPressed: Bool) -> Bool {
        character == "\u{1B}" || (commandPressed && (character == "w" || character == "W"))
    }
}
