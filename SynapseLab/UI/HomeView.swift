import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    NavigationLink {
                        OperatorLiveView()
                    } label: {
                        ModeCard(title: "Measure someone's eye",
                                 detail: "Operator mode · back camera and torch, through an eyecup",
                                 symbol: "eye", available: true)
                    }
                    .buttonStyle(.plain)

                    ModeCard(title: "Measure your own eye",
                             detail: "Self-test mode · front camera and screen flash",
                             symbol: "person.crop.circle", available: false, milestone: 4)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ToolTile(title: "Calibrate", symbol: "ruler", milestone: 4)
                        ToolTile(title: "Phantom", symbol: "circle.dashed", milestone: 5)
                        ToolTile(title: "History", symbol: "clock.arrow.circlepath", milestone: 5)
                        NavigationLink {
                            SettingsView()
                        } label: {
                            ToolTile(title: "Settings", symbol: "gearshape", milestone: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                ResearchBanner().padding(.horizontal, 16).padding(.bottom, 8)
            }
            .navigationTitle("SynapseLab")
        }
        .fullScreenCover(isPresented: Binding(get: { !model.safetyAccepted }, set: { _ in })) {
            SafetySheet { model.safetyAccepted = true }
        }
    }
}

private struct ModeCard: View {
    let title: String
    let detail: String
    let symbol: String
    let available: Bool
    var milestone: Int?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(available ? Theme.accent : .secondary)
                .frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                if let milestone, !available {
                    Text("Coming in Milestone \(milestone)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if available { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .glassBackground()
        .opacity(available ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }
}

private struct ToolTile: View {
    let title: String
    let symbol: String
    let milestone: Int?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2)
            Text(title).font(.headline)
            if let milestone {
                Text("Milestone \(milestone)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .glassBackground()
        .opacity(milestone == nil ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HomeView().environment(AppModel()).preferredColorScheme(.dark)
}
