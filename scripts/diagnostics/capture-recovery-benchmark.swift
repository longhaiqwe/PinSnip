// Controlled backend delays; this measures recovery policy, not real system capture latency.
import Foundation
import PinSnipCore

@main struct RecoveryBenchmark {
    static func delayed(_ value: Int, milliseconds: Int) async -> Int {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                continuation.resume(returning: value)
            }
        }
    }
    static func main() async throws {
        print("sample,scenario,elapsed_ms,winner")
        for sample in 0..<3 {
            for (name, primaryMS, fallbackMS) in [("late-primary", 650, 300), ("slow-primary", 1500, 100), ("healthy", 80, 100)] {
                let recovery = CaptureRecovery<Int>()
                let start = ContinuousClock.now
                let value = try await recovery.capture(primary: { await delayed(1, milliseconds: primaryMS) },
                                                       fallback: { await delayed(2, milliseconds: fallbackMS) })
                let elapsed = start.duration(to: .now).components
                let ms = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
                print("\(sample),\(name),\(String(format: "%.3f", ms)),\(value)")
            }
        }
    }
}
