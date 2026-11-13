import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum GIFShareEncoder {
    public enum ExportError: LocalizedError {
        case invalidGIF, encodingFailed, sizeLimitUnreachable
        public var errorDescription: String? {
            switch self {
            case .invalidGIF: "无法读取这张 GIF 动图。"
            case .encodingFailed: "动图压缩失败，原文件未修改。"
            case .sizeLimitUnreachable: "无法在保留完整时长的情况下达到体积上限，请在「GIF 分享大小」中调高上限。"
            }
        }
    }

    private struct Frame {
        let index: Int
        var ticks: Int
    }

    public static func encode(_ data: Data, settings: GIFShareSettings) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.gif.identifier,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw ExportError.invalidGIF }
        if settings == .original { return data }

        let count = CGImageSourceGetCount(source)
        let scale = min(1,
                        settings.maximumWidth == 0 ? 1 : Double(settings.maximumWidth) / Double(width),
                        settings.maximumHeight == 0 ? 1 : Double(settings.maximumHeight) / Double(height))
        var outputWidth = max(1, Int((Double(width) * scale).rounded(.down)))
        var outputHeight = max(1, Int((Double(height) * scale).rounded(.down)))
        // Standard sharing also respects X's frame and total-pixel recommendations.
        let frameLimit = settings == .standard ? min(350, max(2, 300_000_000 / (outputWidth * outputHeight))) : count
        let withinBytes = settings.maximumBytes == 0 || data.count <= settings.maximumBytes
        if scale == 1, count <= frameLimit, withinBytes { return data }

        let frames = (0..<count).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let seconds = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0.1
            return Frame(index: index, ticks: max(1, Int(((seconds > 0 ? seconds : 0.1) * 100).rounded())))
        }
        let totalTicks = frames.reduce(0) { $0 + $1.ticks }
        var targetCount = min(count, frameLimit)
        // Small-file settings begin at at most 10 fps; each discarded frame's time
        // remains in the preceding frame so the recording is never sped up or cut.
        if settings.maximumBytes > 0, settings.maximumBytes <= 2_000_000 {
            targetCount = min(targetCount, max(2, totalTicks / 10))
        }

        for _ in 0..<8 {
            let selected = selectFrames(frames, count: targetCount, totalTicks: totalTicks)
            let result = try render(source, frames: selected, width: outputWidth, height: outputHeight)
            if settings.maximumBytes == 0 || result.count <= settings.maximumBytes { return result }
            // Retry from the original source, never from an already quantized GIF.
            let ratio = min(0.85, max(0.35, sqrt(Double(settings.maximumBytes) / Double(result.count)) * 0.9))
            let nextWidth = max(1, Int(Double(outputWidth) * ratio))
            let nextHeight = max(1, Int(Double(outputHeight) * ratio))
            if min(nextWidth, nextHeight) >= 64 {
                outputWidth = nextWidth
                outputHeight = nextHeight
            } else if targetCount > 2 {
                targetCount = max(2, targetCount / 2)
            } else { break }
        }
        throw ExportError.sizeLimitUnreachable
    }

    private static func selectFrames(_ frames: [Frame], count: Int, totalTicks: Int) -> [Frame] {
        guard count < frames.count else { return frames }
        var selected: [Frame] = []
        var elapsed = 0
        var lastBucket = -1
        // Reserve the last output slot for the actual final frame, including
        // recordings that end with a long hold in the same sampling bucket.
        let prefixTicks = max(1, totalTicks - frames[frames.count - 1].ticks)
        for frame in frames.dropLast() {
            let bucket = elapsed * (count - 1) / prefixTicks
            if bucket != lastBucket {
                selected.append(frame)
                lastBucket = bucket
            } else {
                selected[selected.count - 1].ticks += frame.ticks
            }
            elapsed += frame.ticks
        }
        selected.append(frames[frames.count - 1])
        return selected
    }

    private static func render(_ source: CGImageSource, frames: [Frame], width: Int, height: Int) throws -> Data {
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.gif.identifier as CFString, frames.count, nil)
        else { throw ExportError.encodingFailed }
        if let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
           let gif = properties[kCGImagePropertyGIFDictionary] {
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: gif] as CFDictionary)
        }
        for frame in frames {
            let success = autoreleasepool { () -> Bool in
                guard let image = CGImageSourceCreateImageAtIndex(source, frame.index, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let context = CGContext(data: nil, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                guard let image = context.makeImage() else { return false }
                let seconds = Double(frame.ticks) / 100
                CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: seconds,
                    kCGImagePropertyGIFUnclampedDelayTime: seconds
                ]] as CFDictionary)
                return true
            }
            guard success else { throw ExportError.encodingFailed }
        }
        guard CGImageDestinationFinalize(destination) else { throw ExportError.encodingFailed }
        return result as Data
    }
}
