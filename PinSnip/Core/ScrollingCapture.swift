import CoreGraphics
import Foundation

public struct ScrollingCaptureFrame: Equatable {
    public let width: Int
    public let height: Int
    public let rgbaPixels: [UInt8]

    public init(width: Int, height: Int, rgbaPixels: [UInt8]) {
        precondition(width > 0 && height > 0)
        precondition(rgbaPixels.count == width * height * 4)
        self.width = width
        self.height = height
        self.rgbaPixels = rgbaPixels
    }

    public init?(image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard rendered else { return nil }
        self.init(width: width, height: height, rgbaPixels: pixels)
    }
}

public enum ScrollingFrameAnalysis: Equatable, Sendable {
    case unchanged
    case scrolled(pixelOffset: Int)
    case unmatched
}

public enum ScrollingCaptureExclusionPolicy {
    public static func canStartCapture(ownApplicationCount: Int) -> Bool {
        ownApplicationCount > 0
    }
}

public enum ScrollingCaptureControlState: Equatable, Sendable {
    case preparing
    case capturing
    case exporting

    public var allowsCancellation: Bool {
        self != .exporting
    }

    public var allowsOutput: Bool {
        self == .capturing
    }
}

public enum ScrollingFrameAnalyzer {
    private static let unchangedThreshold = 0.004
    private static let matchedThreshold = 0.08

    public static func analyze(
        previous: ScrollingCaptureFrame,
        current: ScrollingCaptureFrame
    ) -> ScrollingFrameAnalysis {
        guard previous.width == current.width,
              previous.height == current.height
        else { return .unmatched }

        let height = previous.height
        let topInset = max(2, Int(Double(height) * 0.12))
        let bottomInset = max(2, Int(Double(height) * 0.06))
        let unchangedEnd = height - bottomInset
        guard unchangedEnd > topInset else { return .unmatched }
        let columns = sampledColumns(width: previous.width)

        let unchangedScore = score(
            previous: previous,
            current: current,
            offset: 0,
            rowRange: topInset..<unchangedEnd,
            columns: columns,
            retainedRatio: 1
        )
        if unchangedScore <= unchangedThreshold {
            return .unchanged
        }
        let changingColumns = columns.filter { x in
            columnScore(
                previous: previous,
                current: current,
                offset: 0,
                rowRange: topInset..<unchangedEnd,
                x: x
            ) > 0.015
        }
        let matchingColumns = changingColumns.count >= 2
            ? changingColumns
            : columns

        let minimumOverlap = max(8, Int(Double(height) * 0.18))
        let maximumOffset = height - topInset - bottomInset - minimumOverlap
        guard maximumOffset >= 2 else { return .unmatched }

        var bestOffset = 0
        var bestScore = Double.greatestFiniteMagnitude
        for offset in 2...maximumOffset {
            let end = height - bottomInset - offset
            guard end > topInset else { continue }
            let candidateScore = score(
                previous: previous,
                current: current,
                offset: offset,
                rowRange: topInset..<end,
                columns: matchingColumns,
                retainedRatio: 0.8
            )
            if candidateScore < bestScore {
                bestScore = candidateScore
                bestOffset = offset
            }
        }

        guard bestOffset > 0, bestScore <= matchedThreshold else {
            return .unmatched
        }
        return .scrolled(pixelOffset: bestOffset)
    }

    private static func score(
        previous: ScrollingCaptureFrame,
        current: ScrollingCaptureFrame,
        offset: Int,
        rowRange: Range<Int>,
        columns: [Int],
        retainedRatio: Double
    ) -> Double {
        var columnScores: [Double] = columns.map { x in
            columnScore(
                previous: previous,
                current: current,
                offset: offset,
                rowRange: rowRange,
                x: x
            )
        }

        guard !columnScores.isEmpty else { return .greatestFiniteMagnitude }
        columnScores.sort()
        let retainedCount = max(
            1,
            Int(ceil(Double(columnScores.count) * retainedRatio))
        )
        return columnScores.prefix(retainedCount).reduce(0, +) / Double(retainedCount)
    }

    private static func sampledColumns(width: Int) -> [Int] {
        let horizontalInset = max(1, width / 20)
        let horizontalEnd = max(horizontalInset + 1, width - horizontalInset)
        let xStride = max(1, (horizontalEnd - horizontalInset) / 24)
        return Array(
            stride(from: horizontalInset, to: horizontalEnd, by: xStride)
        )
    }

    private static func columnScore(
        previous: ScrollingCaptureFrame,
        current: ScrollingCaptureFrame,
        offset: Int,
        rowRange: Range<Int>,
        x: Int
    ) -> Double {
        let yStride = max(1, rowRange.count / 180)
        var difference = 0
        var channelCount = 0
        for y in stride(
            from: rowRange.lowerBound,
            to: rowRange.upperBound,
            by: yStride
        ) {
            let previousRow = (y + offset) * previous.width * 4
            let currentRow = y * current.width * 4
            let previousIndex = previousRow + x * 4
            let currentIndex = currentRow + x * 4
            difference += abs(
                Int(previous.rgbaPixels[previousIndex])
                    - Int(current.rgbaPixels[currentIndex])
            )
            difference += abs(
                Int(previous.rgbaPixels[previousIndex + 1])
                    - Int(current.rgbaPixels[currentIndex + 1])
            )
            difference += abs(
                Int(previous.rgbaPixels[previousIndex + 2])
                    - Int(current.rgbaPixels[currentIndex + 2])
            )
            channelCount += 3
        }
        guard channelCount > 0 else { return .greatestFiniteMagnitude }
        return Double(difference) / Double(channelCount * 255)
    }
}

public enum ScrollingCaptureAppendResult: Equatable, Sendable {
    case started(totalPixelHeight: Int)
    case unchanged(totalPixelHeight: Int)
    case appended(pixelHeight: Int, totalPixelHeight: Int)
    case unmatched(totalPixelHeight: Int)
    case reachedLimit(totalPixelHeight: Int)
}

public final class ScrollingCaptureAssembler {
    private let maximumPixelCount: Int
    private var width = 0
    private var totalHeight = 0
    private var previousFrame: ScrollingCaptureFrame?
    private var pixelSegments: [[UInt8]] = []

    public init(maximumPixelCount: Int = 24_000_000) {
        self.maximumPixelCount = max(1, maximumPixelCount)
    }

    @discardableResult
    public func append(_ image: CGImage) -> ScrollingCaptureAppendResult {
        guard let frame = ScrollingCaptureFrame(image: image) else {
            return .unmatched(totalPixelHeight: totalHeight)
        }
        guard let previousFrame else {
            guard frame.width * frame.height <= maximumPixelCount else {
                return .reachedLimit(totalPixelHeight: 0)
            }
            width = frame.width
            totalHeight = frame.height
            self.previousFrame = frame
            pixelSegments = [frame.rgbaPixels]
            return .started(totalPixelHeight: totalHeight)
        }

        switch ScrollingFrameAnalyzer.analyze(previous: previousFrame, current: frame) {
        case .unchanged:
            return .unchanged(totalPixelHeight: totalHeight)
        case .unmatched:
            return .unmatched(totalPixelHeight: totalHeight)
        case let .scrolled(pixelOffset):
            guard frame.width == width,
                  width * (totalHeight + pixelOffset) <= maximumPixelCount
            else {
                return .reachedLimit(totalPixelHeight: totalHeight)
            }
            let appendedByteCount = pixelOffset * width * 4
            pixelSegments.append(Array(frame.rgbaPixels.suffix(appendedByteCount)))
            totalHeight += pixelOffset
            self.previousFrame = frame
            return .appended(
                pixelHeight: pixelOffset,
                totalPixelHeight: totalHeight
            )
        }
    }

    public func makeImage() -> CGImage? {
        guard width > 0, totalHeight > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * totalHeight * 4)
        for segment in pixelSegments {
            pixels.append(contentsOf: segment)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: totalHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
