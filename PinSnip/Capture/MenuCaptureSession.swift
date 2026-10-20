import AppKit

/// Freeze the visible menu before ending tracking. Main-queue tasks alone cannot
/// reliably make progress inside NSMenu's nested event loop.
@MainActor
final class MenuCaptureSession {
    enum Failure: Error { case timedOut }

    private let menus: [NSMenu]
    private var captureTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var isFinished = false

    init(menus: [NSMenu]) { self.menus = menus }

    func start(
        timeout: Duration = .seconds(5),
        capture: @escaping @Sendable () async throws -> CGImage,
        completion: @escaping @MainActor @Sendable (Result<CGImage, Error>) -> Void
    ) {
        captureTask = Task.detached { [weak self] in
            let result: Result<CGImage, Error>
            do { result = .success(try await capture()) }
            catch { result = .failure(error) }
            guard !Task.isCancelled else { return }
            RunLoop.main.perform(inModes: [.common]) {
                MainActor.assumeIsolated { self?.finish(result, completion: completion) }
            }
        }
        timeoutTask = Task.detached { [weak self] in
            do { try await Task.sleep(for: timeout) }
            catch { return }
            RunLoop.main.perform(inModes: [.common]) {
                MainActor.assumeIsolated {
                    self?.finish(.failure(Failure.timedOut), completion: completion)
                }
            }
        }
    }

    func cancel() {
        isFinished = true
        captureTask?.cancel()
        timeoutTask?.cancel()
        captureTask = nil
        timeoutTask = nil
    }

    private func finish(
        _ result: Result<CGImage, Error>,
        completion: @escaping @MainActor @Sendable (Result<CGImage, Error>) -> Void
    ) {
        guard !isFinished else { return }
        cancel()
        for menu in menus.reversed() { menu.cancelTrackingWithoutAnimation() }
        // Wait until tracking has unwound before presenting a key window or alert.
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated { completion(result) }
        }
    }
}
