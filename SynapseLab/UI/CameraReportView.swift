import SwiftUI

/// Every candidate camera and format, and why one was chosen. Filled in the
/// first time the Operator camera starts.
struct CameraReportView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let report = model.camera.report
        List {
            if report.backChoice == nil {
                Section {
                    Text("Open “Measure someone's eye” once to start the camera, then come back here.")
                        .foregroundStyle(.secondary)
                }
            }
            if let choice = report.backChoice {
                Section("Back camera choice") {
                    choiceRows(choice)
                }
            }
            if !report.applied.isEmpty {
                Section("Applied (read back from the device)") {
                    ForEach(Array(report.applied.enumerated()), id: \.offset) { _, row in
                        LabeledContent(row.0, value: row.1)
                    }
                }
            }
            if !report.backCandidates.isEmpty {
                Section("Back candidates (\(report.backCandidates.count))") {
                    candidateRows(report.backCandidates, choice: report.backChoice)
                }
            }
            if let choice = report.frontChoice {
                Section("Front camera (for Self-test, Milestone 4)") {
                    choiceRows(choice)
                }
            }
            if !report.frontCandidates.isEmpty {
                Section("Front candidates (\(report.frontCandidates.count))") {
                    candidateRows(report.frontCandidates, choice: report.frontChoice)
                }
            }
        }
        .font(.callout.monospacedDigit())
        .navigationTitle("Camera Report")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: plainText(report)) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share Camera Report")
            }
        }
        .onAppear { model.camera.refresh() }
    }

    @ViewBuilder
    private func choiceRows(_ choice: FormatChoice) -> some View {
        if let c = choice.chosen {
            LabeledContent("Camera", value: "\(c.deviceKind.rawValue) · \(c.deviceName)")
            LabeledContent("Format", value: c.label)
            LabeledContent("Running at", value: "\(Int(choice.fps)) fps")
        }
        if choice.usedFallback {
            Label("No 120 fps format qualified; using the 60 fps fallback.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
        }
        Text(choice.reason).foregroundStyle(.secondary)
    }

    private func candidateRows(_ candidates: [FormatCandidate], choice: FormatChoice?) -> some View {
        ForEach(candidates) { c in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("\(c.deviceKind.rawValue) · \(c.label)")
                    if c.id == choice?.chosen?.id {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                            .accessibilityLabel("Chosen")
                    }
                }
                Text(detail(c, choice: choice)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func detail(_ c: FormatCandidate, choice: FormatChoice?) -> String {
        let focus = c.minimumFocusDistanceMm < 0 ? "focus n/a" : "focus ≥ \(c.minimumFocusDistanceMm) mm"
        let range = c.isFullRange ? "full range" : "video range"
        let why = c.id == choice?.chosen?.id ? "chosen" : (choice?.rejections[c.id] ?? "")
        return "\(focus) · \(range) · \(why)"
    }

    /// Plain text for sharing, so device values can be sent back when debugging.
    private func plainText(_ r: CameraReport) -> String {
        var lines = ["SynapseLab Camera Report", ""]
        if let c = r.backChoice {
            lines.append("Back choice: \(c.chosen.map { "\($0.deviceKind.rawValue) \($0.label)" } ?? "none") at \(Int(c.fps)) fps")
            lines.append("Reason: \(c.reason)")
        }
        lines.append("")
        lines.append("Applied:")
        for (k, v) in r.applied { lines.append("  \(k): \(v)") }
        lines.append("")
        lines.append("Back candidates:")
        for c in r.backCandidates { lines.append("  \(c.deviceKind.rawValue) \(c.label) — \(detail(c, choice: r.backChoice))") }
        lines.append("")
        if let c = r.frontChoice {
            lines.append("Front choice: \(c.chosen.map { "\($0.deviceKind.rawValue) \($0.label)" } ?? "none") at \(Int(c.fps)) fps")
        }
        lines.append("Front candidates:")
        for c in r.frontCandidates { lines.append("  \(c.deviceKind.rawValue) \(c.label) — \(detail(c, choice: r.frontChoice))") }
        return lines.joined(separator: "\n")
    }
}
