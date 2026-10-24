import AppKit
import Observation
import SwiftUI
import TidyDeskCore

@MainActor
@Observable
final class SwitcherModel {
    typealias Group = TilingCoordinator.SwitcherGroup

    let groups: [Group]
    private let navigation: SwitcherNavigation
    private(set) var position: SwitcherPosition?

    init(groups: [Group]) {
        self.groups = groups
        navigation = SwitcherNavigation(groupSizes: groups.map(\.entries.count))
        position = navigation.first
    }

    var selectedID: WindowID? {
        guard let position, groups.indices.contains(position.group),
              groups[position.group].entries.indices.contains(position.index)
        else { return nil }
        return groups[position.group].entries[position.index].id
    }

    func move(_ move: SwitcherMove) {
        guard let position else { return }
        self.position = navigation.move(position, move)
    }

    func select(number: Int) {
        if let target = navigation.position(atFlat: number - 1) { position = target }
    }

    func select(_ id: WindowID) {
        for (group, value) in groups.enumerated() {
            if let index = value.entries.firstIndex(where: { $0.id == id }) {
                position = SwitcherPosition(group: group, index: index)
            }
        }
    }

    /// 1-based reading-order number for the quick-pick badge; only the first nine can be typed.
    func number(of id: WindowID) -> Int? {
        var count = 0
        for group in groups {
            for entry in group.entries {
                count += 1
                if entry.id == id { return count <= 9 ? count : nil }
            }
        }
        return nil
    }
}

@MainActor
final class SwitcherController {
    private let presenter = FloatingPanelPresenter()

    func show(groups: [SwitcherModel.Group], onSelect: @escaping (WindowID) -> Void) {
        let model = SwitcherModel(groups: groups)
        presenter.present(
            SwitcherView(
                model: model,
                onActivate: { [weak self] id in
                    self?.presenter.dismiss()
                    onSelect(id)
                },
                onDismiss: { [weak self] in self?.presenter.dismiss() }),
            anchor: .center)
    }
}

struct SwitcherView: View {
    let model: SwitcherModel
    let onActivate: (WindowID) -> Void
    let onDismiss: () -> Void

    @FocusState private var hasFocus: Bool
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.groups.isEmpty {
                Label("No windows to switch to", systemImage: "rectangle.dashed")
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            ForEach(model.groups) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Label(group.displayName, systemImage: "display").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ForEach(group.entries) { entry in card(entry) }
                    }
                }
            }
            Text("← → ↑ ↓ choose   ·   1–9 jump   ·   ⏎ switch   ·   esc close")
                .font(.caption).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(22)
        .glassPanel(cornerRadius: 26)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.95)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .focusable()
        .focusEffectDisabled()
        .focused($hasFocus)
        .onAppear {
            hasFocus = true
            withAnimation(.smooth(duration: 0.2)) { appeared = true }
        }
        .onKeyPress(.leftArrow) { move(.left) }
        .onKeyPress(.rightArrow) { move(.right) }
        .onKeyPress(.upArrow) { move(.up) }
        .onKeyPress(.downArrow) { move(.down) }
        .onKeyPress(.tab) { move(.right) }
        .onKeyPress(.return) {
            if let id = model.selectedID { onActivate(id) }
            return .handled
        }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard let number = Int(press.characters) else { return .ignored }
            model.select(number: number)
            if let id = model.selectedID { onActivate(id) }
            return .handled
        }
    }

    private func move(_ move: SwitcherMove) -> KeyPress.Result {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) { model.move(move) }
        return .handled
    }

    private func card(_ entry: TilingCoordinator.SwitcherEntry) -> some View {
        let isSelected = model.selectedID == entry.id
        return VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let icon = entry.icon {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "app").resizable().scaledToFit().padding(8)
                    }
                }
                .frame(width: 56, height: 56)
                if let number = model.number(of: entry.id) {
                    Text("\(number)").font(.caption2.weight(.semibold)).monospacedDigit()
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.thinMaterial, in: Capsule())
                        .offset(x: 8, y: -4)
                }
            }
            Text(entry.appName).font(.callout.weight(.medium)).lineLimit(1)
            Text(entry.title.isEmpty ? " " : entry.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 128)
        .padding(.vertical, 12).padding(.horizontal, 8)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.2))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2))
                    .matchedGeometryEffect(id: "selection", in: selection)
            }
        }
        .scaleEffect(isSelected && !reduceMotion ? 1.04 : 1)
        .contentShape(Rectangle())
        .onTapGesture { onActivate(entry.id) }
        .onHover { if $0 { model.select(entry.id) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.appName) \(entry.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
