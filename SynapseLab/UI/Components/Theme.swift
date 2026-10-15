import SwiftUI

enum Theme {
    /// The single accent: a calm teal.
    static let accent = Color(red: 0.20, green: 0.78, blue: 0.74)
    static let warning = Color.orange
    static let failure = Color.red
    static let leftEye = Color.blue
    static let rightEye = Color.orange
}

/// Liquid Glass on iOS 26 or later, a solid material before that.
struct GlassBackground<S: Shape>: ViewModifier {
    var shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

extension View {
    func glassBackground<S: Shape>(_ shape: S) -> some View {
        modifier(GlassBackground(shape: shape))
    }

    func glassBackground() -> some View {
        modifier(GlassBackground(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)))
    }
}

/// Permanent research notice on every test and result screen (safety rule).
struct ResearchBanner: View {
    var body: some View {
        Label("Research prototype. Not for diagnosis or clinical decisions.",
              systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.black)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warning, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}
