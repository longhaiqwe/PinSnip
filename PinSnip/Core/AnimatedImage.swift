import CoreGraphics
import Foundation
import ImageIO

public struct AnimatedImage {
    public struct Frame {
        public let image: CGImage
        public let duration: TimeInterval

        public init(image: CGImage, duration: TimeInterval) {
            self.image = image
            self.duration = duration
        }
    }

    public let frames: [Frame]
    public let loopCount: Int

    public var pixelWidth: Int { frames[0].image.width }
    public var pixelHeight: Int { frames[0].image.height }

    public init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 1
        else { return nil }

        var decodedFrames: [Frame] = []
        decodedFrames.reserveCapacity(CGImageSourceGetCount(source))
        for index in 0..<CGImageSourceGetCount(source) {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
            decodedFrames.append(Frame(image: image, duration: Self.frameDuration(source: source, index: index)))
        }

        frames = decodedFrames
        loopCount = Self.loopCount(source: source)
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return 0.1 }

        let duration = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
            ?? (gif[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
            ?? 0.1
        return duration > 0 ? duration : 0.1
    }

    private static func loopCount(source: CGImageSource) -> Int {
        guard let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any],
              let loopCount = gif[kCGImagePropertyGIFLoopCount] as? NSNumber
        else { return 0 }
        return loopCount.intValue
    }
}
