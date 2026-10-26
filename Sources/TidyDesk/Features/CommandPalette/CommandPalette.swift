import Observation
import SwiftUI
import TidyDeskCore

struct PaletteCommand: Identifiable {
    let item: CommandItem
    let run: () -> Void
    var id: String { item.id }
}

@MainActor
@Observable
final class PaletteModel {
    let commands: [PaletteCommand]
    var query = "" { didSet { if query != oldValue { selectedID = results.first?.id } } }
    var selectedID: String?

    init(commands: [PaletteCommand]) {
        self.commands = commands
        selectedID = commands.first?.id
    }

    var results: [PaletteCommand] {
        let byID = Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0) })
        return CommandSearch.rank(query, in: commands.map(\.item)).compactMap { byID[$0.id] }
    }

    func move(_ offset: Int) {
        let list = results
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == selectedID } ?? 0
        selectedID = list[((index + offset) % list.count + list.count) % list.count].id
    }

    var selected: PaletteCommand? { results.first { $0.id == selectedID } }
}

struct CommandPaletteView: View {
    let model: PaletteModel
    let onRun: (PaletteCommand) -> Void
    let onDismiss: () -> Void

    @FocusState private var fieldFocused: Bool
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search commands", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($fieldFocused)
                    .onKeyPress(.upArrow) { model.move(-1); return .handled }
                    .onKeyPress(.downArrow) { model.move(1); return .handled }
                    .onKeyPress(.escape) { onDismiss(); return .handled }
                    .onSubmit { if let selected = model.selected { onRun(selected) } }
                    .accessibilityLabel("Search commands")
            }
            .padding(16)
            Divider().opacity(0.4)
            results
        }
        .frame(width: 560, height: 400, alignment: .top)
        .glassPanel(cornerRadius: 22)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.96)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .onAppear {
            fieldFocused = true
            withAnimation(.smooth(duration: 0.18)) { appeared = true }
        }
    }

    @ViewBuilder private var results: some View {
        let list = model.results
        if list.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "questionmark.circle").font(.largeTitle).foregroundStyle(.secondary)
                Text("No matching commands").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(list) { command in row(command) }
                    }
                    .padding(8)
                }
                .onChange(of: model.selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy(duration: 0.15)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func row(_ command: PaletteCommand) -> some View {
        let isSelected = command.id == model.selectedID
        return HStack {
            Text(command.item.title)
            Spacer()
            if let shortcut = command.item.shortcutText {
                Text(shortcut).font(.callout.monospaced()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isSelected ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onRun(command) }
        .id(command.id)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
