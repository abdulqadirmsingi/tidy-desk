import AppKit
import SwiftUI
import TidyDeskCore

struct SuggestionActions {
    var primary: () -> Void
    var secondary: (() -> Void)?
    var dismiss: () -> Void
}

struct SuggestionToastView: View {
    let kind: SuggestionKind
    let actions: SuggestionActions

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(Color.accentColor).frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(primaryLabel) { actions.primary() }.glassButton(prominent: true)
                    if let secondaryLabel, let secondary = actions.secondary {
                        Button(secondaryLabel) { secondary() }.glassButton()
                    }
                    Button(dismissLabel) { actions.dismiss() }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(width: 460, alignment: .leading)
        .glassPanel(cornerRadius: 22)
        .offset(y: appeared || reduceMotion ? 0 : -24)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .onAppear { withAnimation(.smooth(duration: 0.35)) { appeared = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    private var symbol: String {
        switch kind {
        case .grantAccess: "hand.raised.fill"
        case .tidyUp: "rectangle.split.2x2.fill"
        }
    }

    private var title: String {
        switch kind {
        case .grantAccess: "\(Branding.name) can’t arrange windows yet"
        case let .tidyUp(count): "Tidy up \(count) windows?"
        }
    }

    private var subtitle: String {
        switch kind {
        case .grantAccess: "Allow Accessibility access and your windows will arrange themselves."
        case .tidyUp: "Automatic tiling is off. \(Branding.name) can place them side by side for you."
        }
    }

    private var primaryLabel: String {
        switch kind {
        case .grantAccess: "Fix Access"
        case .tidyUp: "Always Arrange Automatically"
        }
    }

    private var secondaryLabel: String? {
        switch kind {
        case .grantAccess: nil
        case .tidyUp: "Arrange Once"
        }
    }

    private var dismissLabel: String {
        switch kind {
        case .grantAccess: "Later"
        case .tidyUp: "Not Now"
        }
    }
}

/// Shows one suggestion at a time just below the menu bar (and below the notch on notched Macs).
/// It never takes focus, so the window the user is working in stays active.
@MainActor
final class ToastPresenter {
    private static let visibleFor: Duration = .seconds(14)
    private static let topInset: CGFloat = 12

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    var isShowing: Bool { panel != nil }

    func show<Content: View>(_ content: Content, onTimeout: @escaping () -> Void) {
        dismiss()
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        host.setFrameSize(size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        if let screen = NSScreen.main {
            // visibleFrame already excludes the menu bar and the notch area.
            let origin = NSPoint(
                x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - Self.topInset)
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
        self.panel = panel
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleFor)
            guard !Task.isCancelled else { return }
            self?.dismiss()
            onTimeout()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}
