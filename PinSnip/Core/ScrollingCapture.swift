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

public enum ScrollingCaptureScrollPlan {
    public static func step(selectionHeight: CGFloat) -> Int {
        Int(max(1, min(320, selectionHeight * 0.35)))
    }

    public static func pulses(distance: Int) -> [Int] {
        guard distance != 0 else { return [] }
        let magnitude = abs(distance)
        let count = min(3, magnitude)
        return (0..<count).map { index in
            (distance < 0 ? -1 : 1) * (magnitude / count + (index < magnitude % count ? 1 : 0))
        }
    }
}

public enum ScrollingFrameAnalyzer {
    private static let unchangedThreshold = 0.004
    private static let matchedThreshold = 0.08

    public static func analyze(
        previous: ScrollingCaptureFrame,
        current: ScrollingCaptureFrame
    ) -> ScrollingFrameAnalysis {
        alignment(previous: previous, current: current).analysis
    }

    /// Locate the moving viewport from the frames instead of assuming fixed header/footer ratios.
    static func alignment(previous: ScrollingCaptureFrame, current: ScrollingCaptureFrame)
        -> (analysis: ScrollingFrameAnalysis, scrollingRows: Range<Int>) {
        let fullRange = 0..<previous.height
        guard previous.width == current.width, previous.height == current.height else {
            return (.unmatched, fullRange)
        }
        let columns = sampledColumns(width: previous.width)
        let unchangedScore = score(previous: previous, current: current, offset: 0,
                                   rowRange: fullRange, columns: columns, retainedRatio: 1)
        if unchangedScore == 0 { return (.unchanged, fullRange) }
        let changingColumns = columns.filter { x in
            columnScore(previous: previous, current: current, offset: 0,
                        rowRange: fullRange, x: x) > 0.015
        }
        let matchingColumns = changingColumns.count >= 2 ? changingColumns : columns
        let changingRows = fullRange.filter { y in
            score(previous: previous, current: current, offset: 0, rowRange: y..<(y + 1),
                  columns: matchingColumns, retainedRatio: 1) > 0.001
        }
        guard let first = changingRows.first, let last = changingRows.last else {
            return (.unchanged, fullRange)
        }
        let scrollingRows = first..<(last + 1)
        let minimumOverlap = max(1, min(8, scrollingRows.count / 2),
                                 Int(Double(scrollingRows.count) * 0.18))
        let maximumOffset = scrollingRows.count - minimumOverlap
        guard maximumOffset >= 1 else { return (.unmatched, scrollingRows) }

        var candidateScores: [(offset: Int, score: Double)] = []
        var bestOffset = 0
        var bestScore = Double.greatestFiniteMagnitude
        for offset in 1...maximumOffset {
            let candidateScore = score(previous: previous, current: current, offset: offset,
                rowRange: first..<(last + 1 - offset), columns: matchingColumns, retainedRatio: 0.8)
            candidateScores.append((offset, candidateScore))
            if candidateScore < bestScore {
                bestScore = candidateScore
                bestOffset = offset
            }
        }
        // A one-pixel translation can have a tiny mean difference; try alignment before
        // treating small differences as capture noise.
        if unchangedScore <= unchangedThreshold && bestScore >= unchangedScore * 0.5 {
            return (.unchanged, scrollingRows)
        }
        guard bestOffset > 0, bestScore <= matchedThreshold else {
            return (.unmatched, scrollingRows)
        }
        // Repeated rows can match several distances exactly. Guessing the distance
        // silently removes complete repeats; let the capture loop retry a smaller move.
        if candidateScores.contains(where: {
            abs($0.offset - bestOffset) > 2 && $0.score <= bestScore + 0.0005
        }) {
            return (.unmatched, scrollingRows)
        }
        return (.scrolled(pixelOffset: bestOffset), scrollingRows)
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
        // Never skip rows when deciding whether anything moved: a thin line can
        // translate one pixel entirely between the coarse offset-search samples.
        let yStride = offset == 0 ? 1 : max(1, rowRange.count / 180)
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

/// No movement cannot distinguish a page bottom from an ignored scroll event.
/// Yield to manual scrolling instead of exporting a potentially incomplete image.
public struct ScrollingCaptureAutomaticProgress {
    private var unchangedAttempts = 0
    private var requiresManualScrolling = false

    public init() {}

    /// Returns true once automatic scrolling should yield to the user.
    public mutating func observe(
        _ result: ScrollingCaptureAppendResult,
        isForwardAttempt: Bool
    ) -> Bool {
        guard !requiresManualScrolling else { return true }
        if isForwardAttempt, case .unchanged = result {
            unchangedAttempts += 1
            requiresManualScrolling = unchangedAttempts >= 2
        } else {
            unchangedAttempts = 0
        }
        return requiresManualScrolling
    }
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

        let alignment = ScrollingFrameAnalyzer.alignment(previous: previousFrame, current: frame)
        switch alignment.analysis {
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
            // Replace the previous fixed footer with new content and the latest footer.
            // Keeping the old footer here inserts a separator at every stitched frame.
            let footerHeight = frame.height - alignment.scrollingRows.upperBound
            removeTrailingBytes(footerHeight * width * 4)
            let appendedByteCount = (pixelOffset + footerHeight) * width * 4
            pixelSegments.append(Array(frame.rgbaPixels.suffix(appendedByteCount)))
            totalHeight += pixelOffset
            self.previousFrame = frame
            return .appended(
                pixelHeight: pixelOffset,
                totalPixelHeight: totalHeight
            )
        }
    }

    private func removeTrailingBytes(_ count: Int) {
        var remaining = count
        while remaining > 0, let last = pixelSegments.last {
            if last.count <= remaining {
                remaining -= last.count
                pixelSegments.removeLast()
            } else {
                pixelSegments[pixelSegments.count - 1].removeLast(remaining)
                remaining = 0
            }
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
