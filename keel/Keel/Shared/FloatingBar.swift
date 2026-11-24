import SwiftUI

/// A screen's own action buttons in a floating glass bar at the bottom.
///
/// The system bottom toolbar sits in the same spot as the Focus bar (tab bar accessory), so on Mac and iPad
/// the Focus bar covered buttons like Reply and the canvas tools. This bar lives in the screen's own safe
/// area instead, so it always sits above the Focus bar and the tab bar.
struct FloatingBar<Bar: View>: ViewModifier {
    @ViewBuilder var bar: () -> Bar
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 18) { bar() }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 18).padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: Capsule())
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
        }
    }
}

extension View {
    func floatingBar<Bar: View>(@ViewBuilder _ bar: @escaping () -> Bar) -> some View {
        modifier(FloatingBar(bar: bar))
    }
}
