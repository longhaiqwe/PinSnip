import Foundation

public enum CaptureRecoveryError: LocalizedError {
    case timedOut
    case busy

    public var errorDescription: String? {
        switch self {
        case .timedOut: return "两种截图方式都未能及时返回画面，请稍后重试。"
        case .busy: return "系统仍在处理之前的截图，请稍后重试。"
        }
    }
}

/// Bounds interactive capture latency even when a native callback never arrives.
public actor CaptureRecovery<Value: Sendable> {
    private let primaryTimeout: Duration
    private let fallbackTimeout: Duration
    private var primaryID: UUID?
    private var fallbackID: UUID?

    public init(primaryTimeout: Duration = .milliseconds(600), fallbackTimeout: Duration = .seconds(3)) {
        self.primaryTimeout = primaryTimeout
        self.fallbackTimeout = fallbackTimeout
    }

    /// One optional warm-up may occupy the primary, but never the recovery backend.
    /// A foreground request can immediately capture fresh fallback pixels if needed.
    public func prewarm(primary: @escaping @Sendable () async throws -> Value) async {
        guard primaryID == nil, !Task.isCancelled else { return }
        let id = UUID()
        primaryID = id
        defer { primaryFinished(id) }
        // Discard pixels and errors: warm-up must neither cache a frame nor present UI.
        _ = try? await primary()
    }

    public func capture(
        primary: @escaping @Sendable () async throws -> Value,
        fallback: @escaping @Sendable () async throws -> Value,
        shouldFallback: @escaping @Sendable (Error) -> Bool = { !($0 is CancellationError) }
    ) async throws -> Value {
        try Task.checkCancellation()
        // A previous native callback may still be outstanding after cancellation.
        // Never share its old pixels with a new request, or enqueue duplicate work.
        guard primaryID == nil else {
            return try await CaptureDeadline<Value>.run(timeout: fallbackTimeout) {
                try await self.captureFallback(fallback)
            }
        }

        let id = UUID()
        primaryID = id
        let primaryTask = Task.detached(priority: .userInitiated) {
            do {
                let value = try await primary()
                await self.primaryFinished(id)
                return value
            } catch {
                await self.primaryFinished(id)
                throw error
            }
        }
        defer { primaryTask.cancel() }
        do {
            return try await CaptureDeadline<Value>.run(timeout: primaryTimeout) {
                try await primaryTask.value
            }
        } catch {
            try Task.checkCancellation()
            guard shouldFallback(error) else { throw error }
        }

        // The delay starts recovery; it does not invalidate a still-running primary.
        // Whichever backend succeeds first supplies this request's fresh pixels.
        return try await CaptureDeadline<Value>.firstSuccess(
            timeout: fallbackTimeout,
            primary: { try await primaryTask.value },
            fallback: { try await self.captureFallback(fallback) },
            shouldFallback: shouldFallback
        )
    }

    private func captureFallback(_ operation: @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        guard fallbackID == nil else { throw CaptureRecoveryError.busy }
        let id = UUID()
        fallbackID = id
        defer { fallbackFinished(id) }
        return try await operation()
    }

    private func primaryFinished(_ id: UUID) {
        if primaryID == id { primaryID = nil }
    }

    private func fallbackFinished(_ id: UUID) {
        if fallbackID == id { fallbackID = nil }
    }
}

/// A task group would wait for a canceled child whose system callback is stuck.
/// Resolve the caller once, without joining that child; CaptureRecovery bounds
/// outstanding work to one operation per backend until real completion.
private final class CaptureDeadline<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var tasks: [Task<Void, Never>] = []
    private var failureCount = 0

    static func run(
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let deadline = CaptureDeadline()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                deadline.install(continuation)
                let worker = Task.detached(priority: .userInitiated) {
                    do { deadline.resolve(.success(try await operation())) }
                    catch { deadline.resolve(.failure(error)) }
                }
                let timer = Task.detached {
                    do { try await Task.sleep(for: timeout) }
                    catch { return }
                    deadline.resolve(.failure(CaptureRecoveryError.timedOut))
                }
                deadline.track([worker, timer])
            }
        } onCancel: {
            deadline.resolve(.failure(CancellationError()))
        }
    }

    static func firstSuccess(
        timeout: Duration,
        primary: @escaping @Sendable () async throws -> Value,
        fallback: @escaping @Sendable () async throws -> Value,
        shouldFallback: @escaping @Sendable (Error) -> Bool
    ) async throws -> Value {
        let deadline = CaptureDeadline()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                deadline.install(continuation)
                let workers = [primary, fallback].map { operation in
                    Task.detached(priority: .userInitiated) {
                        do {
                            try Task.checkCancellation()
                            deadline.resolve(.success(try await operation()))
                        } catch {
                            deadline.reject(error, recoverable: shouldFallback(error))
                        }
                    }
                }
                let timer = Task.detached {
                    do { try await Task.sleep(for: timeout) }
                    catch { return }
                    deadline.resolve(.failure(CaptureRecoveryError.timedOut))
                }
                deadline.track(workers + [timer])
            }
        } onCancel: {
            deadline.resolve(.failure(CancellationError()))
        }
    }

    private func reject(_ error: Error, recoverable: Bool) {
        let bothFailed = lock.withLock {
            failureCount += 1
            return failureCount == 2
        }
        if !recoverable || bothFailed { resolve(.failure(error)) }
    }

    private func install(_ continuation: CheckedContinuation<Value, Error>) {
        let completed = lock.withLock { () -> Result<Value, Error>? in
            if let result { return result }
            self.continuation = continuation
            return nil
        }
        if let completed { continuation.resume(with: completed) }
    }

    private func track(_ tasks: [Task<Void, Never>]) {
        let completed = lock.withLock {
            if result != nil { return true }
            self.tasks = tasks
            return false
        }
        if completed { tasks.forEach { $0.cancel() } }
    }

    private func resolve(_ result: Result<Value, Error>) {
        let delivery = lock.withLock { () -> (CheckedContinuation<Value, Error>?, [Task<Void, Never>])? in
            guard self.result == nil else { return nil }
            self.result = result
            let delivery = (continuation, tasks)
            continuation = nil
            tasks = []
            return delivery
        }
        guard let (continuation, tasks) = delivery else { return }
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}
