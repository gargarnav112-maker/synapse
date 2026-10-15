import SwiftUI

@main
struct SynapseLabApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
