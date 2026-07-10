import SwiftUI

extension View {
    /// Liquid Glass surface: real glass on macOS 26+, material glass on 15.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 14) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }

    /// Capsule-shaped glass, used for the floating action bar.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: .capsule)
                .overlay(Capsule().strokeBorder(.separator.opacity(0.5)))
        }
    }
}
