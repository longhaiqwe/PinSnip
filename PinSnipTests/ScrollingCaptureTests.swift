import XCTest
@testable import PinSnipCore

final class ScrollingCaptureTests: XCTestCase {
    func testAutomaticCaptureWaitsForManualScrollingWhenFirstAttemptsDoNotMove() {
        var progress = ScrollingCaptureAutomaticProgress()
        XCTAssertFalse(progress.observe(.unchanged(totalPixelHeight: 60), isForwardAttempt: true))
        XCTAssertTrue(progress.observe(.unchanged(totalPixelHeight: 60), isForwardAttempt: true))
        // Waiting may last indefinitely, and manual scrolling must remain possible.
        XCTAssertTrue(progress.observe(.unchanged(totalPixelHeight: 60), isForwardAttempt: false))
        XCTAssertTrue(progress.observe(.appended(pixelHeight: 20, totalPixelHeight: 80), isForwardAttempt: false))
    }

    func testAutomaticCapturePauseAfterProgressRequiresUserCompletion() {
        var progress = ScrollingCaptureAutomaticProgress()
        XCTAssertFalse(progress.observe(.appended(pixelHeight: 20, totalPixelHeight: 80), isForwardAttempt: true))
        XCTAssertFalse(progress.observe(.unchanged(totalPixelHeight: 80), isForwardAttempt: true))
        XCTAssertTrue(progress.observe(.unchanged(totalPixelHeight: 80), isForwardAttempt: true))
    }

    func testRecoveryAndSuccessfulAppendResetNoMovementCount() {
        for resetResult: ScrollingCaptureAppendResult in [
            .unchanged(totalPixelHeight: 60),
            .unmatched(totalPixelHeight: 60),
            .appended(pixelHeight: 20, totalPixelHeight: 80),
        ] {
            var progress = ScrollingCaptureAutomaticProgress()
            XCTAssertFalse(progress.observe(.unchanged(totalPixelHeight: 60), isForwardAttempt: true))
            XCTAssertFalse(progress.observe(resetResult, isForwardAttempt: false))
            XCTAssertFalse(progress.observe(.unchanged(totalPixelHeight: 80), isForwardAttempt: true))
            XCTAssertTrue(progress.observe(.unchanged(totalPixelHeight: 80), isForwardAttempt: true))
        }
    }

    func testPreparingControlsAllowCancellationButNotOutput() {
        XCTAssertTrue(ScrollingCaptureControlState.preparing.allowsCancellation)
        XCTAssertFalse(ScrollingCaptureControlState.preparing.allowsOutput)
    }

    func testCapturingControlsAllowCancellationAndOutput() {
        XCTAssertTrue(ScrollingCaptureControlState.capturing.allowsCancellation)
        XCTAssertTrue(ScrollingCaptureControlState.capturing.allowsOutput)
    }

    func testExportingControlsDisableCancellationAndOutput() {
        XCTAssertFalse(ScrollingCaptureControlState.exporting.allowsCancellation)
        XCTAssertFalse(ScrollingCaptureControlState.exporting.allowsOutput)
    }

    func testDoesNotStartWhenOwnApplicationCannotBeExcluded() {
        XCTAssertFalse(
            ScrollingCaptureExclusionPolicy.canStartCapture(
                ownApplicationCount: 0
            )
        )
    }

    func testStartsWhenOwnApplicationCanBeExcluded() {
        XCTAssertTrue(
            ScrollingCaptureExclusionPolicy.canStartCapture(
                ownApplicationCount: 1
            )
        )
    }

    func testDetectsVerticalOffsetBetweenContentFrames() {
        let previous = frame(rows: Array(0..<60))
        let current = frame(rows: Array(20..<80))

        XCTAssertEqual(
            ScrollingFrameAnalyzer.analyze(previous: previous, current: current),
            .scrolled(pixelOffset: 20)
        )
    }

    func testIgnoresAStickyHeaderWhenMatchingScrolledContent() {
        let previous = frame(rows: Array(repeating: 240, count: 8) + Array(0..<52))
        let current = frame(rows: Array(repeating: 240, count: 8) + Array(20..<72))

        XCTAssertEqual(
            ScrollingFrameAnalyzer.analyze(previous: previous, current: current),
            .scrolled(pixelOffset: 20)
        )
    }

    func testIgnoresFixedSidebarColumnsWhenMatchingScrolledContent() {
        let fixedRows = Array(100..<160)
        let previous = frameWithFixedSidebar(
            fixedRows: fixedRows,
            contentRows: Array(0..<60)
        )
        let current = frameWithFixedSidebar(
            fixedRows: fixedRows,
            contentRows: Array(20..<80)
        )

        XCTAssertEqual(
            ScrollingFrameAnalyzer.analyze(previous: previous, current: current),
            .scrolled(pixelOffset: 20)
        )
    }

    func testUsesNarrowChangingContentInsteadOfUniformMargins() {
        let previous = frameWithNarrowContent(rows: Array(0..<60))
        let current = frameWithNarrowContent(rows: Array(20..<80))

        XCTAssertEqual(
            ScrollingFrameAnalyzer.analyze(previous: previous, current: current),
            .scrolled(pixelOffset: 20)
        )
    }

    func testReportsUnchangedFrames() {
        let frame = frame(rows: Array(0..<60))

        XCTAssertEqual(
            ScrollingFrameAnalyzer.analyze(previous: frame, current: frame),
            .unchanged
        )
    }

    func testRejectsUnrelatedFrames() {
        let previous = frame(rows: Array(0..<60))
        let unrelated = frame(rows: Array((0..<60).reversed()))

        XCTAssertEqual(
            ScrollingFrameAnalyzer.analyze(previous: previous, current: unrelated),
            .unmatched
        )
    }

    func testAssemblerAppendsOnlyNewPixels() throws {
        let assembler = ScrollingCaptureAssembler(maximumPixelCount: 10_000)

        XCTAssertEqual(
            assembler.append(try image(rows: Array(0..<60))),
            .started(totalPixelHeight: 60)
        )
        XCTAssertEqual(
            assembler.append(try image(rows: Array(20..<80))),
            .appended(pixelHeight: 20, totalPixelHeight: 80)
        )

        let result = try XCTUnwrap(assembler.makeImage())
        XCTAssertEqual(result.width, 8)
        XCTAssertEqual(result.height, 80)
        XCTAssertEqual(try rowValue(in: result, y: 0), 0)
        XCTAssertEqual(try rowValue(in: result, y: 59), 59)
        XCTAssertEqual(try rowValue(in: result, y: 79), 79)
    }

    func testAssemblerDoesNotAppendAnUnchangedFrame() throws {
        let image = try image(rows: Array(0..<60))
        let assembler = ScrollingCaptureAssembler(maximumPixelCount: 10_000)
        _ = assembler.append(image)

        XCTAssertEqual(
            assembler.append(image),
            .unchanged(totalPixelHeight: 60)
        )
        XCTAssertEqual(assembler.makeImage()?.height, 60)
    }

    func testAssemblerStopsBeforeExceedingPixelBudget() throws {
        let assembler = ScrollingCaptureAssembler(maximumPixelCount: 8 * 70)
        _ = assembler.append(try image(rows: Array(0..<60)))

        XCTAssertEqual(
            assembler.append(try image(rows: Array(20..<80))),
            .reachedLimit(totalPixelHeight: 60)
        )
        XCTAssertEqual(assembler.makeImage()?.height, 60)
    }

    func testKeepsFixedFooterOnlyOnceWithoutLosingContentRows() throws {
        let footer = Array(240..<248)
        let assembler = ScrollingCaptureAssembler()
        _ = assembler.append(try image(rows: Array(0..<52) + footer))
        _ = assembler.append(try image(rows: Array(20..<72) + footer))
        _ = assembler.append(try image(rows: Array(40..<92) + footer))
        let result = try XCTUnwrap(assembler.makeImage())
        XCTAssertEqual(result.height, 100)
        let actual = try XCTUnwrap(ScrollingCaptureFrame(image: result))
        let rows = (0..<result.height).map { Int(actual.rgbaPixels[$0 * actual.width * 4]) }
        XCTAssertEqual(rows, Array(0..<92) + footer)
    }

    func testTallFixedHeaderDoesNotCorruptMatching() {
        let header = Array(repeating: 240, count: 40)
        XCTAssertEqual(ScrollingFrameAnalyzer.analyze(
            previous: frame(rows: header + Array(0..<60)),
            current: frame(rows: header + Array(25..<85))), .scrolled(pixelOffset: 25))
    }

    func testPreservesASinglePixelScroll() throws {
        let assembler = ScrollingCaptureAssembler()
        _ = assembler.append(try image(rows: Array(0..<60)))
        XCTAssertEqual(assembler.append(try image(rows: Array(1..<61))),
                       .appended(pixelHeight: 1, totalPixelHeight: 61))
        let result = try XCTUnwrap(assembler.makeImage())
        XCTAssertEqual(try rowValue(in: result, y: result.height - 1), 60)
    }

    func testMatchesLargeScrollWhenSelectionIsShorterThanViewport() {
        XCTAssertEqual(ScrollingFrameAnalyzer.analyze(previous: frame(rows: Array(0..<60)),
            current: frame(rows: Array(45..<105))), .scrolled(pixelOffset: 45))
    }

    func testRejectsAmbiguousRepeatedRowsRatherThanDroppingWholeRepeats() {
        XCTAssertEqual(ScrollingFrameAnalyzer.analyze(
            previous: frame(rows: (0..<90).map { $0 % 9 }),
            current: frame(rows: (3..<93).map { $0 % 9 })), .unmatched)
    }

    func testPreservesBlankRowsBeforeFooterAcrossUnevenScrolls() throws {
        let header = Array(230..<244)
        let footer = Array(245..<250)
        let content = Array(0..<35) + Array(repeating: 220, count: 28) + Array(63..<180)
        let assembler = ScrollingCaptureAssembler()
        for offset in [0, 13, 14, 32] {
            _ = assembler.append(try image(rows: header + Array(content[offset..<(offset + 70)]) + footer))
        }
        let result = try XCTUnwrap(assembler.makeImage())
        let actual = try XCTUnwrap(ScrollingCaptureFrame(image: result))
        let rows = (0..<result.height).map { Int(actual.rgbaPixels[$0 * actual.width * 4]) }
        XCTAssertEqual(rows, header + Array(content[0..<102]) + footer)
    }

    func testShortSelectionsKeepEnoughOverlapInsteadOfForcingAn80PointJump() {
        XCTAssertLessThanOrEqual(ScrollingCaptureScrollPlan.step(selectionHeight: 20), 7)
        XCTAssertGreaterThanOrEqual(ScrollingCaptureScrollPlan.step(selectionHeight: 3), 1)
    }

    func testScrollPulsesPreserveExactDistanceIncludingRecovery() {
        for distance in [1, 2, 5, 80, -1, -7] {
            let pulses = ScrollingCaptureScrollPlan.pulses(distance: distance)
            XCTAssertEqual(pulses.reduce(0, +), distance)
            XCTAssertTrue(pulses.allSatisfy { distance > 0 ? $0 > 0 : $0 < 0 })
        }
    }

    func testSinglePixelMovementOfASparseLineIsNotSkippedByRowSampling() {
        var previousRows = Array(repeating: 240, count: 600)
        var currentRows = previousRows
        previousRows[101] = 0
        currentRows[100] = 0
        XCTAssertEqual(ScrollingFrameAnalyzer.analyze(previous: frame(rows: previousRows),
            current: frame(rows: currentRows)), .scrolled(pixelOffset: 1))
    }

    private func frame(rows: [Int], width: Int = 24) -> ScrollingCaptureFrame {
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * rows.count * 4)
        for row in rows {
            for x in 0..<width {
                pixels.append(UInt8((row * 17 + x * 29) % 251))
                pixels.append(UInt8((row * 31 + x * 7) % 253))
                pixels.append(UInt8((row * 11 + x * 19) % 255))
                pixels.append(255)
            }
        }
        return ScrollingCaptureFrame(
            width: width,
            height: rows.count,
            rgbaPixels: pixels
        )
    }

    private func frameWithFixedSidebar(
        fixedRows: [Int],
        contentRows: [Int],
        width: Int = 24
    ) -> ScrollingCaptureFrame {
        precondition(fixedRows.count == contentRows.count)
        let sidebarWidth = width / 3
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * contentRows.count * 4)
        for y in contentRows.indices {
            for x in 0..<width {
                let row = x < sidebarWidth ? fixedRows[y] : contentRows[y]
                pixels.append(UInt8((row * 17 + x * 29) % 251))
                pixels.append(UInt8((row * 31 + x * 7) % 253))
                pixels.append(UInt8((row * 11 + x * 19) % 255))
                pixels.append(255)
            }
        }
        return ScrollingCaptureFrame(
            width: width,
            height: contentRows.count,
            rgbaPixels: pixels
        )
    }

    private func frameWithNarrowContent(
        rows: [Int],
        width: Int = 40
    ) -> ScrollingCaptureFrame {
        let contentRange = (width * 3 / 8)..<(width * 5 / 8)
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * rows.count * 4)
        for row in rows {
            for x in 0..<width {
                let value = contentRange.contains(x) ? row : 240
                pixels.append(UInt8((value * 17 + x * 29) % 251))
                pixels.append(UInt8((value * 31 + x * 7) % 253))
                pixels.append(UInt8((value * 11 + x * 19) % 255))
                pixels.append(255)
            }
        }
        return ScrollingCaptureFrame(
            width: width,
            height: rows.count,
            rgbaPixels: pixels
        )
    }

    private func image(rows: [Int], width: Int = 8) throws -> CGImage {
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * rows.count * 4)
        for row in rows {
            let channel = UInt8(row % 256)
            for _ in 0..<width {
                pixels.append(channel)
                pixels.append(channel)
                pixels.append(channel)
                pixels.append(255)
            }
        }
        let data = Data(pixels) as CFData
        let provider = try XCTUnwrap(CGDataProvider(data: data))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        return try XCTUnwrap(
            CGImage(
                width: width,
                height: rows.count,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
    }

    private func rowValue(in image: CGImage, y: Int) throws -> UInt8 {
        let frame = try XCTUnwrap(ScrollingCaptureFrame(image: image))
        return frame.rgbaPixels[y * frame.width * 4]
    }
}
