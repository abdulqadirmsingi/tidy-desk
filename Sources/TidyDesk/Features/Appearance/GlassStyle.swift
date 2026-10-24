import AppKit
import SwiftUI

/// Window-behind blur. The hosting window must be non-opaque with a clear background.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Frosted window backdrop with slow drifting color. Falls back to a plain background when the user
/// has Reduce Transparency on, and holds still under Reduce Motion.
struct AmbientGlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            if reduceTransparency {
                Rectangle().fill(.background)
            } else {
                VisualEffectBackground()
                GeometryReader { proxy in
                    ZStack {
                        blob(.blue, size: proxy.size.width * 0.7, x: drift ? 0.15 : 0.3, y: drift ? 0.2 : 0.05, in: proxy.size)
                        blob(.purple, size: proxy.size.width * 0.6, x: drift ? 0.85 : 0.7, y: drift ? 0.75 : 0.95, in: proxy.size)
                        blob(.teal, size: proxy.size.width * 0.45, x: drift ? 0.75 : 0.9, y: drift ? 0.1 : 0.3, in: proxy.size)
                    }
                    .blur(radius: 70)
                    .opacity(0.45)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) { drift = true }
        }
        .accessibilityHidden(true)
    }

    private func blob(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat, in container: CGSize) -> some View {
        Circle().fill(color.gradient).frame(width: size, height: size)
            .position(x: container.width * x, y: container.height * y)
    }
}

extension View {
    /// A translucent rounded panel: Liquid Glass on macOS 26, frosted material before that.
    func glassPanel(cornerRadius: CGFloat = 20) -> some View { modifier(GlassPanel(cornerRadius: cornerRadius)) }

    /// Glass button on macOS 26, standard bordered button before that.
    @ViewBuilder func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

private struct GlassPanel: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.ultraThinMaterial), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(contrast == .increased ? 0.5 : 0.18), lineWidth: 1))
        }
    }
}
