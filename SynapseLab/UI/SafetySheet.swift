import SwiftUI

/// First-launch safety sheet. No test can run until it is accepted.
struct SafetySheet: View {
    var onAccept: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.warning)
                    .accessibilityHidden(true)
                Text("Before you start")
                    .font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 14) {
                    point("flask", "SynapseLab is a research prototype. It does not diagnose anything and must not guide clinical decisions.")
                    point("person.2", "Only test people who agree to be tested.")
                    point("bolt.trianglebadge.exclamationmark",
                          "Do not test anyone with epilepsy or light sensitivity, an eye injury, or recent eye surgery.")
                    point("light.max", "Each test uses a 200 ms flash of light. Flashes are at least 20 seconds apart, with no more than 10 in 10 minutes.")
                    point("hand.raised", "Stop straight away if it causes any discomfort.")
                    point("lock.iphone", "Recordings stay on this phone unless you export them.")
                }
                Button(action: onAccept) {
                    Text("I understand")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .padding(24)
        }
        .interactiveDismissDisabled()
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
        }
    }
}

#Preview { SafetySheet(onAccept: {}) }
