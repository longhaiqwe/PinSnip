import AppKit
import SwiftUI
import ImageIO
import PinSnipCore

struct ShelfGIFPreview: NSViewRepresentable {
    let url: URL
    let placeholder: NSImage
    let isPlaying: Bool

    func makeNSView(context: Context) -> ShelfGIFPreviewView {
        let view = ShelfGIFPreviewView(frame: .zero)
        view.configure(url: url, placeholder: placeholder, isPlaying: isPlaying)
        return view
    }

    func updateNSView(_ view: ShelfGIFPreviewView, context: Context) {
        view.configure(url: url, placeholder: placeholder, isPlaying: isPlaying)
    }

    static func dismantleNSView(_ view: ShelfGIFPreviewView, coordinator: ()) {
        view.stopPlayback()
    }
}

@MainActor
final class ShelfGIFPreviewView: NSImageView {
    static let maximumThumbnailDimension = Int(2 * ShelfLayout.maxPhotoWidth)
    private(set) var frameIndex = 0
    private var animationURL: URL?
    private var placeholder: NSImage?
    private var source: CGImageSource?
    private var frameTimer: Timer?
    private var playbackRequested = false

    var isAnimating: Bool { frameTimer != nil }

    func configure(url: URL, placeholder: NSImage, isPlaying: Bool) {
        if animationURL != url {
            suspendPlayback()
            animationURL = url
        }
        self.placeholder = placeholder
        playbackRequested = isPlaying
        imageScaling = .scaleProportionallyUpOrDown
        if isPlaying, window != nil { startPlaybackIfNeeded() }
        else { suspendPlayback() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, playbackRequested { startPlaybackIfNeeded() }
        else { suspendPlayback() }
    }

    func stopPlayback() {
        playbackRequested = false
        suspendPlayback()
    }

    private func suspendPlayback() {
        frameTimer?.invalidate()
        frameTimer = nil
        source = nil
        frameIndex = 0
        image = placeholder
    }

    private func startPlaybackIfNeeded() {
        guard frameTimer == nil else { return }
        guard let animationURL,
              let source = CGImageSourceCreateWithURL(animationURL as CFURL, [
                kCGImageSourceShouldCache: false
              ] as CFDictionary),
              CGImageSourceGetCount(source) > 1
        else { image = placeholder; return }
        self.source = source
        frameIndex = 0
        guard renderFrame() else { suspendPlayback(); return }
        scheduleNextFrame()
    }

    private func renderFrame() -> Bool {
        // Keep only the current thumbnail, not every full-resolution GIF frame.
        guard let source,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, frameIndex, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.maximumThumbnailDimension,
                kCGImageSourceShouldCache: false
              ] as CFDictionary)
        else { return false }
        image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
        return true
    }

    private func scheduleNextFrame() {
        guard let source, playbackRequested, window != nil else { return }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, frameIndex, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let duration = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
            ?? 0.1
        let timer = Timer(timeInterval: max(0.02, duration), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceFrame() }
        }
        frameTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceFrame() {
        frameTimer = nil
        guard let source, playbackRequested, window != nil else { suspendPlayback(); return }
        frameIndex = (frameIndex + 1) % CGImageSourceGetCount(source)
        guard renderFrame() else { suspendPlayback(); return }
        scheduleNextFrame()
    }
}
