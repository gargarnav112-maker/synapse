import SwiftUI

/// Milestone 1 Operator screen: live back-camera preview with the Lab HUD,
/// settle-and-lock, a 200 ms torch flash on demand, and the 30-second
/// frame-rate check. Pupil tracking and the full test arrive in Milestones 2–3.
struct OperatorLiveView: View {
    @Environment(AppModel.self) private var model
    @State private var showHUD = true
    @State private var busy = false

    private var camera: CameraController { model.camera }
    private var stats: CameraStats { camera.stats }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .accessibilityLabel("Live camera preview")

            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    if showHUD { LabHUDView(stats: stats) }
                    Spacer()
                    statePill
                }
                if let check = stats.fpsCheck { FPSCheckCard(check: check) }
                Spacer()
                if let message = camera.errorMessage {
                    Text(message)
                        .font(.callout)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.failure.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { camera.clearError() }
                        .accessibilityHint("Tap to dismiss")
                }
                controls
                ResearchBanner()
            }
            .padding(16)
        }
        .navigationTitle("Operator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(showHUD ? "Hide Lab" : "Lab") { showHUD.toggle() }
            }
        }
        .task {
            await camera.start(workingDistanceCm: model.workingDistanceCm, torchBaseline: model.torchBaseline)
            await camera.pollStats()
        }
        .onDisappear { camera.stop() }
        .persistentSystemOverlays(.hidden)
    }

    private var statePill: some View {
        Text(stats.status)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassBackground(Capsule())
            .accessibilityLabel("Camera state \(stats.status)")
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if stats.locked == nil {
                controlButton("Lock", symbol: "lock", enabled: stats.running && !stats.isSettling) {
                    await camera.lock()
                }
            } else {
                controlButton("Unlock", symbol: "lock.open", enabled: !stats.isFlashing) {
                    await camera.unlock()
                }
            }
            controlButton("Flash", symbol: "light.max",
                          enabled: stats.running && stats.torchAvailable && !stats.isFlashing && !stats.isSettling) {
                await camera.flash()
            }
            controlButton("fps check", symbol: "speedometer", enabled: stats.running) {
                camera.startFPSCheck()
            }
        }
        .disabled(busy || camera.isStarting)
    }

    private func controlButton(_ title: String, symbol: String, enabled: Bool,
                               action: @escaping () async -> Void) -> some View {
        Button {
            Task {
                busy = true
                await action()
                busy = false
            }
        } label: {
            Label(title, systemImage: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.plain)
        .glassBackground(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Live progress and verdict of the 30-second frame-rate check.
private struct FPSCheckCard: View {
    let check: FPSCheck

    var body: some View {
        let progress = min(check.elapsed / Tuning.fpsCheckSeconds, 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(check.finished ? (check.passed ? "fps check passed" : "fps check failed") : "fps check running")
                    .font(.headline)
                    .foregroundStyle(check.finished ? (check.passed ? Theme.accent : Theme.failure) : .primary)
                Spacer()
                if check.finished {
                    Image(systemName: check.passed ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(check.passed ? Theme.accent : Theme.failure)
                }
            }
            ProgressView(value: progress)
            Text(String(format: "%.0f s · mean %.1f fps (need ≥ %.0f) · dropped %.2f%% (need < %.0f%%)",
                        check.elapsed, check.meanFPS, Tuning.fpsCheckMinFPS,
                        check.dropFraction * 100, Tuning.fpsCheckMaxDropFraction * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .glassBackground()
        .accessibilityElement(children: .combine)
    }
}
