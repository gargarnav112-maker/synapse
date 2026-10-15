import SwiftUI

/// Exposes the machinery: frame rate, drops, exposure, ISO, lens, torch,
/// thermal state and lock state, so any reading can be checked by eye.
/// Detector fields (ms per frame, inlier rays, residual, flags) arrive with
/// the detector in Milestone 2.
struct LabHUDView: View {
    let stats: CameraStats

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("fps", String(format: "%.1f / %.0f", stats.measuredFPS, stats.targetFPS),
                warn: stats.running && stats.measuredFPS > 0 && stats.measuredFPS < stats.targetFPS - 2)
            row("dropped", "\(stats.framesDropped) (" + String(format: "%.2f%%", stats.dropFraction * 100) + ")",
                warn: stats.dropFraction >= Tuning.fpsCheckMaxDropFraction)
            row("frames", "\(stats.framesDelivered)")
            row("format", stats.formatLabel.isEmpty ? "—" : stats.formatLabel)
            row("exposure", exposureText(stats.exposureSeconds))
            row("ISO", String(format: "%.0f", stats.iso))
            row("lens", String(format: "%.3f", stats.lensPosition))
            row("torch", stats.torchAvailable ? String(format: "%.2f", stats.torchLevel) : "n/a")
            row("thermal", thermalText, warn: stats.thermal == .serious || stats.thermal == .critical)
            row("state", stats.status)
            if let l = stats.locked {
                Divider().overlay(.white.opacity(0.3))
                row("locked exp", exposureText(l.exposureSeconds))
                row("locked ISO", String(format: "%.0f", l.iso))
                row("locked lens", String(format: "%.3f", l.lensPosition))
                row("auto was", "\(exposureText(l.autoExposureSeconds)) · ISO \(Int(l.autoISO))")
                let drift = stats.drift
                row("drift", drift.isEmpty ? "none" : drift.joined(separator: ", "), warn: !drift.isEmpty)
            }
            if let f = stats.lastFlash {
                Divider().overlay(.white.opacity(0.3))
                row("last flash", String(format: "%.1f ms at %.2f", f.durationMs, f.peakLevel))
            }
            if stats.usedFallbackFPS {
                Label("No 120 fps format: running at 60 fps", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
            }
        }
        .font(.caption.monospacedDigit())
        .padding(10)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lab HUD")
    }

    private var thermalText: String {
        switch stats.thermal {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private func exposureText(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        return String(format: "1/%.0f s (%.0f µs)", 1 / seconds, seconds * 1e6)
    }

    private func row(_ name: String, _ value: String, warn: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(name).foregroundStyle(.white.opacity(0.65)).frame(width: 82, alignment: .leading)
            Text(value).foregroundStyle(warn ? Theme.warning : .white)
        }
        .accessibilityElement(children: .combine)
    }
}
