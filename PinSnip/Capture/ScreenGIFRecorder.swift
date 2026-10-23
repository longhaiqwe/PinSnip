import AppKit
import CoreMedia
import CoreVideo
import PinSnipCore
import ScreenCaptureKit

@MainActor
final class ScreenGIFRecorder {
    // 40 ms is exactly representable by GIF's centisecond timing.
    static let framesPerSecond = 25.0
    static let maximumDuration: TimeInterval = 30
    // Keep Retina detail for common selections (up to 1,200 points at 2x).
    // Bound very large captures to keep the 25 fps cache workload manageable.
    static let maximumPixelDimension: CGFloat = 2_400

    private var stream: SCStream?
    private var output: GIFRecordingStreamOutput?
    private var durationTask: Task<Void, Never>?
    private var sessionID: UUID?
    private var onStopRequested: (() -> Void)?

    func start(
        screen: NSScreen,
        selectionRect: CGRect,
        excludingWindowIDs: Set<CGWindowID> = [],
        onStopRequested: @escaping () -> Void
    ) async throws {
        let id = UUID()
        sessionID = id
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        try Task.checkCancellation()
        guard sessionID == id else { throw CancellationError() }
        guard let displayID = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == displayID })
        else { throw ScreenCaptureError.displayUnavailable }

        // Exclude only recording controls, keeping shelf and pin windows visible.
        let excludedWindows = content.windows.filter { excludingWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let geometry = ScreenRecordingGeometry(
            screenSize: screen.frame.size,
            selectionRect: selectionRect,
            backingScale: screen.backingScaleFactor,
            maximumPixelDimension: Self.maximumPixelDimension
        )
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = geometry.sourceRect
        configuration.width = Int(geometry.outputPixelSize.width)
        configuration.height = Int(geometry.outputPixelSize.height)
        configuration.scalesToFit = true
        configuration.showsCursor = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(Self.framesPerSecond))
        configuration.queueDepth = 5

        let output = try GIFRecordingStreamOutput { [weak self] in
            Task { @MainActor in
                guard let self, self.sessionID == id else { return }
                self.onStopRequested?()
            }
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        self.stream = stream
        self.output = output
        self.onStopRequested = onStopRequested
        do {
            try await stream.startCapture()
            // Do not announce recording until an actual frame is available.
            // This also makes an immediate Stop produce a valid still GIF.
            let deadline = ProcessInfo.processInfo.systemUptime + 5
            while !(await output.hasFrames()) {
                try Task.checkCancellation()
                guard sessionID == id else { throw CancellationError() }
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    throw GIFRecordingStreamOutput.RecordingError.noFrames
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            try Task.checkCancellation()
            guard sessionID == id else { throw CancellationError() }
            durationTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(Self.maximumDuration)) }
                catch { return }
                guard let self, self.sessionID == id else { return }
                self.onStopRequested?()
            }
        } catch {
            // Cancellation can race startCapture: stop again after it returns,
            // even if cancel() already cleared this recorder's session.
            try? await stream.stopCapture()
            output.discard()
            if sessionID == id { cancel() }
            throw error
        }
    }

    func stop(style: ShareStyle, borderSize: ShareBorderSize = .automatic) async -> Data? {
        let stream = self.stream
        let output = self.output
        // Snapshot the stop time before waiting for the stream to shut down.
        let endTimestamp = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        reset()
        try? await stream?.stopCapture()
        return await output?.encode(
            endTimestamp: endTimestamp,
            fallbackDuration: 1 / Self.framesPerSecond,
            style: style,
            borderSize: borderSize
        )
    }

    func cancel() {
        let stream = self.stream
        let output = self.output
        reset()
        // Close the cache immediately; any late callbacks are ignored.
        output?.discard()
        Task { try? await stream?.stopCapture() }
    }

    private func reset() {
        durationTask?.cancel()
        durationTask = nil
        stream = nil
        output = nil
        sessionID = nil
        onStopRequested = nil
    }
}

/// Avoid spending the capture budget compressing noise that will not shrink.
/// Both paths own their bytes before the capture surface is unlocked/reused.
struct GIFFrameCacheData {
    let data: NSData
    let isCompressed: Bool

    init(copying bytes: UnsafeRawPointer, count: Int) throws {
        let borrowed = NSData(bytesNoCopy: UnsafeMutableRawPointer(mutating: bytes), length: count, freeWhenDone: false)
        let sample: NSData
        if count <= 32_768 {
            sample = borrowed
        } else {
            let chunks = NSMutableData(capacity: 32_768)!
            for index in 0..<8 {
                let offset = (count - 4_096) * index / 7
                chunks.append(bytes.advanced(by: offset), length: 4_096)
            }
            sample = chunks
        }
        let compressedSample = try sample.compressed(using: .lz4)
        if compressedSample.length < sample.length * 9 / 10 {
            let compressed = count <= 32_768 ? compressedSample : try borrowed.compressed(using: .lz4)
            if compressed.length < count {
                data = compressed
                isCompressed = true
                return
            }
        }
        data = NSData(bytes: bytes, length: count)
        isCompressed = false
    }

    static func decode(_ data: NSData, isCompressed: Bool) throws -> NSData {
        isCompressed ? try data.decompressed(using: .lz4) : data
    }
}

/// All mutable state and disk work are confined to `queue`. Capture surfaces are
/// released after a fast lossless copy; no frame or export work runs on MainActor.
final class GIFRecordingStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    enum RecordingError: Error { case noFrames, invalidPixelBuffer, cannotCreateCacheFile }

    let queue = DispatchQueue(label: "com.longhai.pinsnip.gif-recording", qos: .userInitiated)
    private let directory: URL
    private let cacheURL: URL
    private let cacheHandle: FileHandle
    private var cacheOffset: UInt64 = 0
    private let onStopRequested: @Sendable () -> Void
    private var frames: [Frame] = []
    private var closed = false
    private var failed = false

    private struct Frame {
        let url: URL
        let timestamp: TimeInterval
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let isCompressed: Bool
        let offset: UInt64
        let byteCount: Int

        func image() -> CGImage? {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let data = try? handle.read(upToCount: byteCount),
                  data.count == byteCount,
                  let pixels = try? GIFFrameCacheData.decode(data as NSData, isCompressed: isCompressed),
                  let provider = CGDataProvider(data: pixels as CFData)
            else { return nil }
            return CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)],
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            )
        }
    }

    init(onStopRequested: @escaping @Sendable () -> Void) throws {
        self.onStopRequested = onStopRequested
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PinSnip-GIF-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cacheURL = directory.appendingPathComponent("frames.pixels")
        do {
            guard FileManager.default.createFile(atPath: cacheURL.path, contents: nil) else {
                throw RecordingError.cannotCreateCacheFile
            }
            cacheHandle = try FileHandle(forWritingTo: cacheURL)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        super.init()
    }

    deinit {
        try? cacheHandle.close()
        try? FileManager.default.removeItem(at: directory)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer
        else { return }
        append(buffer, timestamp: sampleBuffer.presentationTimeStamp.seconds)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStopRequested()
    }

    // Called only on queue, including by synthetic-frame regression tests.
    func append(_ buffer: CVPixelBuffer, timestamp: TimeInterval) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !closed, !failed, timestamp.isFinite,
              frames.last.map({ timestamp > $0.timestamp }) ?? true
        else { return }
        autoreleasepool {
            do {
                guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
                      CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess
                else { throw RecordingError.invalidPixelBuffer }
                let stored: GIFFrameCacheData
                do {
                    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
                    guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw RecordingError.invalidPixelBuffer }
                    let count = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
                    stored = try GIFFrameCacheData(copying: base, count: count)
                }
                // Append to one disposable cache file. Repeated file creation
                // and close operations can stall capture past its 40 ms budget.
                try cacheHandle.write(contentsOf: stored.data as Data)
                frames.append(Frame(
                    url: cacheURL, timestamp: timestamp,
                    width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                    isCompressed: stored.isCompressed,
                    offset: cacheOffset, byteCount: stored.data.length
                ))
                cacheOffset += UInt64(stored.data.length)
            } catch {
                failed = true
                onStopRequested()
            }
        }
    }

    func hasFrames() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: !self.frames.isEmpty) }
        }
    }

    func discard() {
        queue.async { self.cleanup() }
    }

    func encode(endTimestamp: TimeInterval, fallbackDuration: TimeInterval, style: ShareStyle, borderSize: ShareBorderSize) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                defer { self.cleanup() }
                guard !self.closed, !self.failed, !self.frames.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                self.closed = true
                do { try self.cacheHandle.close() }
                catch {
                    continuation.resume(returning: nil)
                    return
                }
                // A callback already in flight when Stop was pressed may carry a
                // later PTS. Keep only frames within the requested recording.
                let frames = self.frames.filter { $0.timestamp <= endTimestamp }
                guard !frames.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                var durations = GIFFrameTimeline.durations(
                    for: frames.map(\.timestamp), fallbackDuration: fallbackDuration,
                    endTimestamp: endTimestamp
                )
                let count = max(2, frames.count)
                if frames.count == 1 {
                    // GIF needs two frames. Split a static interval instead of
                    // doubling its playback time.
                    let half = max(0.02, durations[0] / 2)
                    durations = [half, half]
                }
                let data = AnimatedGIFEncoder.encodeRecording(
                    frameCount: count, style: style, borderSize: borderSize
                ) { index in
                    guard let image = frames[min(index, frames.count - 1)].image() else { return nil }
                    return AnimatedImage.Frame(image: image, duration: durations[index])
                }
                continuation.resume(returning: data)
            }
        }
    }

    private func cleanup() {
        closed = true
        frames.removeAll()
        try? cacheHandle.close()
        try? FileManager.default.removeItem(at: directory)
    }
}
