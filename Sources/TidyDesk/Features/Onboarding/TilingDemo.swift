import SwiftUI
import TidyDeskCore

/// A miniature desktop that tiles placeholder windows with the app's real layout engine, so what the
/// tour shows is exactly what the app does.
struct TilingDemo: View {
    var kind: LayoutKind
    /// Windows shown; when `autoplay` is on this is driven by the demo itself.
    var count: Int = 4
    var autoplay = false
    var startOffset = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 1

    private static let canvas = CGSize(width: 1600, height: 1000)
    private static let sequence = [1, 2, 3, 4, 3, 2]
    private static let stepDelay: Duration = .milliseconds(1500)

    private var visibleCount: Int { autoplay && !reduceMotion ? shown : (autoplay ? 4 : count) }

    var body: some View {
        let settings = DisplaySettings(layout: kind, maxWindows: 4, spacing: 36, margin: 36)
        let windows = (0..<visibleCount).map { _ in PlannerWindow(id: WindowID()) }
        let frames = TilePlanner.plan(
            windows: windows, settings: settings, area: CGRect(origin: .zero, size: Self.canvas)
        ).tileFrames

        GeometryReader { proxy in
            let scale = min(proxy.size.width / Self.canvas.width, proxy.size.height / Self.canvas.height)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.18))
                ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                    MiniWindow(index: index)
                        .frame(width: frame.width * scale, height: frame.height * scale)
                        .offset(x: frame.minX * scale, y: frame.minY * scale)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: Self.canvas.width * scale, height: Self.canvas.height * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
        .animation(reduceMotion ? nil : .spring(duration: 0.65, bounce: 0.22), value: visibleCount)
        .animation(reduceMotion ? nil : .spring(duration: 0.65, bounce: 0.22), value: kind)
        .task(id: autoplay && !reduceMotion) {
            guard autoplay, !reduceMotion else { return }
            var index = startOffset
            while !Task.isCancelled {
                shown = Self.sequence[index % Self.sequence.count]
                index += 1
                try? await Task.sleep(for: Self.stepDelay)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Animated preview: \(visibleCount) windows arranged as \(kind.title)")
    }
}

private struct MiniWindow: View {
    let index: Int
    private static let palette: [Color] = [.blue, .purple, .teal, .orange]

    var body: some View {
        let color = Self.palette[index % Self.palette.count]
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color.gradient.opacity(0.75))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(.white.opacity(0.7)).frame(width: 4, height: 4) }
                }
                .padding(5)
            }
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
    }
}
