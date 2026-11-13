import AppKit
import PinSnipCore

@MainActor
final class PinWindowController: NSWindowController, NSWindowDelegate, NSMenuDelegate {
    private let image: CGImage
    private let animation: AnimatedImage?
    private let imageView: PinImageView
    private let baseSize: NSSize
    private(set) var transformState = PinTransform()
    var onClose: (() -> Void)?
    var isClickThroughEnabled: Bool {
        window?.ignoresMouseEvents == true
    }

    convenience init(image: CGImage, frame: NSRect) {
        self.init(image: image, animation: nil, frame: frame)
    }

    convenience init(animation: AnimatedImage, frame: NSRect) {
        self.init(image: animation.frames[0].image, animation: animation, frame: frame)
    }

    private init(image: CGImage, animation: AnimatedImage?, frame: NSRect) {
        self.image = image
        self.animation = animation
        self.imageView = if let animation {
            PinImageView(animation: animation)
        } else {
            PinImageView(image: image)
        }
        self.baseSize = frame.size

        let panel = PinPanel(
            contentRect: frame,
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
        imageView.setAnimationPaused(false)
    }

    func setHidden(_ hidden: Bool) {
        hidden ? window?.orderOut(nil) : window?.orderFrontRegardless()
        imageView.setAnimationPaused(hidden)
    }

    func makeInteractive() {
        window?.ignoresMouseEvents = false
    }

    func windowWillClose(_ notification: Notification) {
        imageView.stopAnimating()
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
        guard let window else { return }
        window.ignoresMouseEvents.toggle()
        if window.ignoresMouseEvents {
            TransientFeedback.show(message: "已开启鼠标穿透。可在 PinSnip 菜单栏选择「截图与贴图管理 → 关闭贴图鼠标穿透」。")
        }
    }

    @objc private func toggleTopmost() {
        guard let window else { return }
        window.level = window.level == .floating ? .normal : .floating
    }

    @objc private func copyImage() {
        copyOriginal()
    }

    @objc private func saveImage() {
        if let animation {
            CaptureOutputService.saveGIF(animation.sourceData)
        } else {
            CaptureOutputService.saveRendered(image)
        }
    }

    func copyOriginal(
        to pasteboard: NSPasteboard = .general,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        if let animation {
            CaptureOutputService.copyGIF(animation.sourceData, to: pasteboard, completion: completion)
        } else {
            CaptureOutputService.copyRendered(image, to: pasteboard)
            completion(true)
        }
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
        menu.delegate = self
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
        let opacityItem = NSMenuItem(title: "不透明度", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacity
        menu.addItem(opacityItem)
        menu.addItem(.separator())
        let clickThrough = item("鼠标穿透", action: #selector(toggleClickThrough), key: "x")
        clickThrough.toolTip = "开启后可从菜单栏「截图与贴图管理」关闭鼠标穿透"
        menu.addItem(clickThrough)
        menu.addItem(item("置顶", action: #selector(toggleTopmost)))
        menu.addItem(.separator())
        menu.addItem(item(animation == nil ? "复制原图" : "复制原动图", action: #selector(copyImage)))
        menu.addItem(item(animation == nil ? "保存原图…" : "保存原动图…", action: #selector(saveImage)))
        menu.addItem(item("关闭贴图", action: #selector(closePin), key: "w"))
        imageView.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let opacity = transformState.opacity * 100
        for entry in menu.items {
            switch entry.action {
            case #selector(flipHorizontal): entry.state = transformState.isFlippedHorizontally ? .on : .off
            case #selector(flipVertical): entry.state = transformState.isFlippedVertically ? .on : .off
            case #selector(toggleTopmost): entry.state = window?.level == .floating ? .on : .off
            case #selector(toggleClickThrough): entry.state = isClickThroughEnabled ? .on : .off
            default:
                guard let choices = entry.submenu else { continue }
                entry.title = "不透明度（\(Int(opacity.rounded()))%）"
                for choice in choices.items {
                    choice.state = abs(opacity - CGFloat(choice.tag)) < 0.001 ? .on : .off
                }
            }
        }
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
