import AVFoundation
import Observation

/// Main-actor face of `CameraEngine` for SwiftUI: starts and stops it, runs
/// lock / flash / checks, and copies its stats at 10 Hz for the Lab HUD.
@MainActor
@Observable
final class CameraController {
    let engine = CameraEngine()

    private(set) var stats = CameraStats()
    private(set) var report = CameraReport()
    private(set) var errorMessage: String?
    private(set) var isStarting = false

    var session: AVCaptureSession { engine.session }

    func start(workingDistanceCm: Double, torchBaseline: Float) async {
        guard !isStarting else { return }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }
        do {
            try await engine.start(workingDistanceCm: workingDistanceCm, torchBaseline: torchBaseline)
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func stop() {
        engine.stop()
    }

    /// Polls the engine while the view is visible; cancelled with the view's task.
    func pollStats() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: .seconds(Tuning.hudRefreshSeconds))
        }
    }

    func refresh() {
        stats = engine.snapshot()
        report = engine.report()
    }

    func lock() async {
        await run { _ = try await self.engine.settleAndLock() }
    }

    func unlock() async {
        await run { try await self.engine.unlock() }
    }

    func flash() async {
        await run { _ = try await self.engine.flash() }
    }

    func setTorchBaseline(_ level: Float) {
        engine.setTorchBaseline(level)
    }

    func startFPSCheck() {
        engine.startFPSCheck()
        refresh()
    }

    func clearError() { errorMessage = nil }

    private func run(_ work: () async throws -> Void) async {
        errorMessage = nil
        do { try await work() } catch { errorMessage = error.localizedDescription }
        refresh()
    }
}
