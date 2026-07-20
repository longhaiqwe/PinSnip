import AppKit
import PinSnipCore

@MainActor
final class PinWindowController: NSWindowController, NSWindowDelegate {
    private let image: CGImage
    private let imageView: PinImageView
    private let baseSize: NSSize
    private(set) var transformState = PinTransform()
    var onClose: (() -> Void)?

    init(image: CGImage, origin: NSPoint) {
        self.image = image
        self.imageView = PinImageView(image: image)
        let naturalSize = NSSize(width: image.width, height: image.height)
        let fit = min(1, min(560 / max(1, naturalSize.width), 420 / max(1, naturalSize.height)))
        self.baseSize = NSSize(width: max(80, naturalSize.width * fit), height: max(60, naturalSize.height * fit))

        let panel = PinPanel(
            contentRect: NSRect(origin: origin, size: baseSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)
        panel.contentView = imageView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        installMenu()

        imageView.onScroll = { [weak self] delta, adjustsOpacity in
            self?.handleScroll(delta: delta, adjustsOpacity: adjustsOpacity)
        }
        imageView.onKeyAction = { [weak self] key, modifiers in
            self?.handleKey(key, modifiers: modifiers)
        }
        applyTransform(keepingCenter: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        showWindow(nil)
        window?.orderFrontRegardless()
    }

    func setHidden(_ hidden: Bool) {
        hidden ? window?.orderOut(nil) : window?.orderFrontRegardless()
    }

    func makeInteractive() {
        window?.ignoresMouseEvents = false
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    @objc private func rotateClockwise() {
        transformState = transformState.rotatedClockwise()
        applyTransform()
    }

    @objc private func rotateCounterclockwise() {
        transformState = transformState.rotatedCounterclockwise()
        applyTransform()
    }

    @objc private func flipHorizontal() {
        transformState = transformState.togglingHorizontalFlip()
        applyTransform()
    }

    @objc private func flipVertical() {
        transformState = transformState.togglingVerticalFlip()
        applyTransform()
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        transformState = transformState.withOpacity(CGFloat(sender.tag) / 100)
        applyTransform()
    }

    @objc private func toggleClickThrough() {
        window?.ignoresMouseEvents.toggle()
    }

    @objc private func toggleTopmost() {
        guard let window else { return }
        window.level = window.level == .floating ? .normal : .floating
    }

    @objc private func copyImage() {
        CaptureOutputService.copy(image)
    }

    @objc private func saveImage() {
        CaptureOutputService.save(image)
    }

    @objc private func closePin() {
        close()
    }

    private func handleScroll(delta: CGFloat, adjustsOpacity: Bool) {
        if adjustsOpacity {
            transformState = transformState.withOpacity(transformState.opacity + (delta > 0 ? 0.05 : -0.05))
        } else {
            transformState = transformState.zoomed(by: delta > 0 ? 1.08 : 0.92)
        }
        applyTransform()
    }

    private func handleKey(_ key: Character, modifiers: NSEvent.ModifierFlags) {
        if PinKeyboardShortcut.shouldClose(
            character: key,
            commandPressed: modifiers.contains(.command)
        ) {
            closePin()
            return
        }

        switch key {
        case "1": rotateClockwise()
        case "2": rotateCounterclockwise()
        case "3": flipHorizontal()
        case "4": flipVertical()
        case "x", "X": toggleClickThrough()
        default: break
        }
    }

    private func applyTransform(keepingCenter: Bool = true) {
        guard let window else { return }
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let rotated = !transformState.rotationQuarterTurns.isMultiple(of: 2)
        let width = (rotated ? baseSize.height : baseSize.width) * transformState.scale
        let height = (rotated ? baseSize.width : baseSize.height) * transformState.scale
        let origin = keepingCenter
            ? NSPoint(x: center.x - width / 2, y: center.y - height / 2)
            : window.frame.origin
        window.setFrame(NSRect(x: origin.x, y: origin.y, width: width, height: height), display: true)
        window.alphaValue = transformState.opacity
        imageView.transformState = transformState
    }

    private func installMenu() {
        let menu = NSMenu()
        menu.addItem(item("顺时针旋转", action: #selector(rotateClockwise), key: "1"))
        menu.addItem(item("逆时针旋转", action: #selector(rotateCounterclockwise), key: "2"))
        menu.addItem(item("水平镜像", action: #selector(flipHorizontal), key: "3"))
        menu.addItem(item("垂直镜像", action: #selector(flipVertical), key: "4"))
        let opacity = NSMenu(title: "透明度")
        for value in [100, 75, 50, 25] {
            let menuItem = item("\(value)%", action: #selector(setOpacity(_:)))
            menuItem.tag = value
            opacity.addItem(menuItem)
        }
        let opacityItem = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacity
        menu.addItem(opacityItem)
        menu.addItem(.separator())
        menu.addItem(item("鼠标穿透", action: #selector(toggleClickThrough), key: "x"))
        menu.addItem(item("切换置顶", action: #selector(toggleTopmost)))
        menu.addItem(.separator())
        menu.addItem(item("复制原图", action: #selector(copyImage)))
        menu.addItem(item("保存原图…", action: #selector(saveImage)))
        menu.addItem(item("关闭贴图", action: #selector(closePin), key: "w"))
        imageView.menu = menu
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}

private final class PinPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
