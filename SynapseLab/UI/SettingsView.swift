import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Stepper(value: $model.workingDistanceCm, in: Tuning.workingDistanceRangeCm, step: 1) {
                    LabeledContent("Working distance", value: "\(Int(model.workingDistanceCm)) cm")
                }
            } footer: {
                Text("Lens-to-eye distance set by your eyecup. Used to pick a camera that can focus that close. Applies the next time the camera starts.")
            }

            Section {
                VStack(alignment: .leading) {
                    LabeledContent("Torch baseline", value: String(format: "%.2f", model.torchBaseline))
                    Slider(value: $model.torchBaseline, in: Tuning.torchBaselineRange, step: 0.01)
                        .onChange(of: model.torchBaseline) { _, level in
                            model.camera.setTorchBaseline(level)
                        }
                }
            } footer: {
                Text("Dim light during the baseline so the eye is visible inside the eyecup. The flash steps to full and back to this level.")
            }

            Section("Camera") {
                NavigationLink("Camera Report") { CameraReportView() }
            }

            Section("About") {
                LabeledContent("Milestone", value: "1 · Camera core")
                Text("Research prototype. Not for diagnosis or clinical decisions.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
