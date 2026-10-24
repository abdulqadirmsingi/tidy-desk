import AppKit
import Observation
import SwiftUI
import TidyDeskCore

@MainActor
@Observable
final class SwitcherModel {
    typealias Group = TilingCoordinator.SwitcherGroup

    let groups: [Group]
    private(set) var selected: WindowID?

    init(groups: [Group]) {
        self.groups = groups
        selected = groups.first?.entries.first?.id
    }

    private var flat: [WindowID] { groups.flatMap { $0.entries.map(\.id) } }

    func moveSelection(by offset: Int) {
        let ids = flat
        guard !ids.isEmpty else { return }
        let index = selected.flatMap { ids.firstIndex(of: $0) } ?? 0
        selected = ids[(index + offset + ids.count) % ids.count]
    }

    func select(_ id: WindowID) { selected = id }
}

/// A panel that can take key events without activating the app, so the previously active window
/// keeps its place if the switcher is dismissed.
private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class SwitcherController {
    private var panel: SwitcherPanel?
    private var resignToken: NSObjectProtocol?

    func show(groups: [SwitcherModel.Group], onSelect: @escaping (WindowID) -> Void) {
        dismiss()
        let model = SwitcherModel(groups: groups)
        let view = SwitcherView(
            model: model,
            onActivate: { [weak self] id in
                self?.dismiss()
                onSelect(id)
            },
            onDismiss: { [weak self] in self?.dismiss() })
        let host = NSHostingView(rootView: view)
        host.setFrameSize(host.fittingSize)

        let panel = SwitcherPanel(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .modalPanel
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        if let screen = NSScreen.main {
            let origin = NSPoint(
                x: screen.frame.midX - panel.frame.width / 2, y: screen.frame.midY - panel.frame.height / 2)
            panel.setFrameOrigin(origin)
        }
        panel.makeKeyAndOrderFront(nil)
        resignToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        self.panel = panel
    }

    func dismiss() {
        if let resignToken { NotificationCenter.default.removeObserver(resignToken) }
        resignToken = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}

struct SwitcherView: View {
    let model: SwitcherModel
    let onActivate: (WindowID) -> Void
    let onDismiss: () -> Void
    @FocusState private var hasFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.groups.isEmpty {
                Label("No windows to switch to", systemImage: "rectangle.dashed")
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            ForEach(model.groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.displayName).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(group.entries) { entry in card(entry) }
                    }
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .focusable()
        .focusEffectDisabled()
        .focused($hasFocus)
        .onAppear { hasFocus = true }
        .onKeyPress(.leftArrow) { model.moveSelection(by: -1); return .handled }
        .onKeyPress(.rightArrow) { model.moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
        .onKeyPress(.tab) { model.moveSelection(by: 1); return .handled }
        .onKeyPress(.return) {
            if let id = model.selected { onActivate(id) }
            return .handled
        }
        .onKeyPress(.escape) { onDismiss(); return .handled }
    }

    private func card(_ entry: TilingCoordinator.SwitcherEntry) -> some View {
        let isSelected = model.selected == entry.id
        return VStack(spacing: 6) {
            if let icon = entry.icon {
                Image(nsImage: icon).resizable().frame(width: 48, height: 48)
            } else {
                Image(systemName: "app").font(.system(size: 36)).frame(width: 48, height: 48)
            }
            Text(entry.appName).font(.callout).lineLimit(1)
            Text(entry.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 130)
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { onActivate(entry.id) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.appName) \(entry.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
