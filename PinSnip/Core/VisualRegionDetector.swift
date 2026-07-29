import CoreGraphics
import Vision

public struct VisualRegionDetector: Sendable {
    private let minimumContrast: CGFloat

    public init(minimumContrast: CGFloat = 0.12) {
        self.minimumContrast = minimumContrast
    }

    public func candidates(
        in image: CGImage,
        viewSize: CGSize
    ) -> [WindowCandidate] {
        guard viewSize.width > 0, viewSize.height > 0,
              let preparedImage = PreparedImage(image)
        else { return [] }

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 32
        request.minimumAspectRatio = 0.12
        request.maximumAspectRatio = 1
        request.minimumSize = 0.05
        request.minimumConfidence = 0.45
        request.quadratureTolerance = 8

        do {
            try VNImageRequestHandler(
                cgImage: preparedImage.image,
                orientation: .up
            ).perform([request])
        } catch {
            return []
        }

        let imageArea = CGFloat(preparedImage.width * preparedImage.height)
        let detected = (request.results ?? []).compactMap { observation -> DetectedRegion? in
            let normalizedRect = observation.boundingBox.standardized
            let pixelRect = CGRect(
                x: normalizedRect.minX * CGFloat(preparedImage.width),
                y: normalizedRect.minY * CGFloat(preparedImage.height),
                width: normalizedRect.width * CGFloat(preparedImage.width),
                height: normalizedRect.height * CGFloat(preparedImage.height)
            )
            let coverage = pixelRect.width * pixelRect.height / imageArea
            guard coverage >= 0.015, coverage <= 0.75,
                  pixelRect.width >= 60, pixelRect.height >= 45
            else { return nil }

            let contrast = preparedImage.borderContrast(around: pixelRect)
            guard contrast >= minimumContrast else { return nil }

            let frame = CGRect(
                x: normalizedRect.minX * viewSize.width,
                y: normalizedRect.minY * viewSize.height,
                width: normalizedRect.width * viewSize.width,
                height: normalizedRect.height * viewSize.height
            ).integral
            guard frame.width >= 80, frame.height >= 60 else { return nil }
            return DetectedRegion(frame: frame, contrast: contrast)
        }

        let deduplicated = detected
            .sorted {
                if $0.contrast != $1.contrast { return $0.contrast > $1.contrast }
                return $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height
            }
            .reduce(into: [DetectedRegion]()) { regions, candidate in
                guard !regions.contains(where: {
                    overlapRatio($0.frame, candidate.frame) >= 0.9
                }) else { return }
                regions.append(candidate)
            }
            .sorted {
                let lhsArea = $0.frame.width * $0.frame.height
                let rhsArea = $1.frame.width * $1.frame.height
                if lhsArea != rhsArea { return lhsArea < rhsArea }
                return $0.contrast > $1.contrast
            }

        return deduplicated.enumerated().map { index, region in
            WindowCandidate(
                id: CGWindowID.max - CGWindowID(index),
                frame: region.frame,
                zOrder: 0,
                kind: .visualRegion
            )
        }
    }
}

private struct DetectedRegion {
    let frame: CGRect
    let contrast: CGFloat
}

private struct PreparedImage {
    let image: CGImage
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(_ source: CGImage) {
        let longestSide = max(source.width, source.height)
        let scale = min(1, 1_024 / CGFloat(longestSide))
        width = max(1, Int((CGFloat(source.width) * scale).rounded()))
        height = max(1, Int((CGFloat(source.height) * scale).rounded()))

        let bytesPerRow = width * 4
        var storage = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &storage,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(
            source,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        guard let rendered = context.makeImage() else { return nil }
        image = rendered
        bytes = storage
    }

    func borderContrast(around rect: CGRect) -> CGFloat {
        let inset = max(2, min(rect.width, rect.height) * 0.015)
        let fractions = stride(from: CGFloat(0.12), through: 0.88, by: 0.095)
        var sideContrasts = [CGFloat]()

        func appendContrast(
            inside: (CGFloat) -> CGPoint,
            outside: (CGFloat) -> CGPoint
        ) {
            let differences = fractions.compactMap { fraction -> CGFloat? in
                guard let inner = luminance(at: inside(fraction)),
                      let outer = luminance(at: outside(fraction))
                else { return nil }
                return abs(inner - outer)
            }
            guard !differences.isEmpty else { return }
            sideContrasts.append(
                differences.reduce(0, +) / CGFloat(differences.count)
            )
        }

        appendContrast(
            inside: { CGPoint(x: rect.minX + inset, y: rect.minY + rect.height * $0) },
            outside: { CGPoint(x: rect.minX - inset, y: rect.minY + rect.height * $0) }
        )
        appendContrast(
            inside: { CGPoint(x: rect.maxX - inset, y: rect.minY + rect.height * $0) },
            outside: { CGPoint(x: rect.maxX + inset, y: rect.minY + rect.height * $0) }
        )
        appendContrast(
            inside: { CGPoint(x: rect.minX + rect.width * $0, y: rect.minY + inset) },
            outside: { CGPoint(x: rect.minX + rect.width * $0, y: rect.minY - inset) }
        )
        appendContrast(
            inside: { CGPoint(x: rect.minX + rect.width * $0, y: rect.maxY - inset) },
            outside: { CGPoint(x: rect.minX + rect.width * $0, y: rect.maxY + inset) }
        )

        guard !sideContrasts.isEmpty else { return 0 }
        return sideContrasts.reduce(0, +) / CGFloat(sideContrasts.count)
    }

    private func luminance(at point: CGPoint) -> CGFloat? {
        let x = Int(point.x.rounded())
        let y = Int(point.y.rounded())
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let offset = (y * width + x) * 4
        let red = CGFloat(bytes[offset]) / 255
        let green = CGFloat(bytes[offset + 1]) / 255
        let blue = CGFloat(bytes[offset + 2]) / 255
        return red * 0.2126 + green * 0.7152 + blue * 0.0722
    }
}

private func overlapRatio(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    let intersection = lhs.intersection(rhs)
    guard !intersection.isNull, !intersection.isEmpty else { return 0 }
    let intersectionArea = intersection.width * intersection.height
    let smallerArea = min(
        lhs.width * lhs.height,
        rhs.width * rhs.height
    )
    return smallerArea > 0 ? intersectionArea / smallerArea : 0
}
