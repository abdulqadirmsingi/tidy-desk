import SwiftUI
import TidyDeskCore

extension OnboardingView {
    @ViewBuilder func content(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome: welcome
        case .permission: permission
        case .grant: grant
        case .verify: verify
        case .layouts: layouts
        case .choose: choose
        case .arrange: arrange
        }
    }

    private func page<Body: View>(_ title: String, _ subtitle: String, @ViewBuilder body: () -> Body) -> some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text(title).font(.system(size: 28, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                Text(subtitle).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            body()
            Spacer(minLength: 0)
        }
    }

    private func fact(_ symbol: String, _ text: String, tint: Color = .accentColor) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint).frame(width: 28)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Steps

    private var welcome: some View {
        page("Windows that arrange themselves", "\(Branding.name) lives in your menu bar and keeps every window neatly placed — and you stay in control.") {
            TilingDemo(kind: .grid, autoplay: true)
                .frame(maxWidth: 340)
                .padding(14)
                .glassPanel()
        }
    }

    private var permission: some View {
        page("One permission, one purpose", "macOS asks you to allow apps to move other apps’ windows.") {
            VStack(alignment: .leading, spacing: 14) {
                fact("rectangle.3.group", "Used only to place and resize your windows.")
                fact("eye.slash", "Never records your screen or reads what’s in your windows.", tint: .green)
                fact("network.slash", "Works fully offline. Nothing is sent anywhere.", tint: .green)
            }
            .padding(22)
            .frame(maxWidth: 460)
            .glassPanel()
        }
    }

    private var grant: some View {
        page("Allow access", "Three quick steps in System Settings.") {
            VStack(alignment: .leading, spacing: 14) {
                fact("1.circle.fill", "Click the button below.")
                fact("2.circle.fill", "Find \(Branding.name) in the Accessibility list.")
                fact("3.circle.fill", "Switch it on. This page continues by itself.")
                HStack {
                    Button("Open Accessibility Settings") {
                        model.permission.requestPrompt()
                        model.permission.openSystemSettings()
                    }
                    .glassButton(prominent: true)
                    Spacer()
                    if granted {
                        Label("Access granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Waiting for access…").foregroundStyle(.secondary) }
                    }
                }
                .padding(.top, 6)
                if !granted && showStaleHelp {
                    Divider().opacity(0.4)
                    StaleGrantHelp().transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(22)
            .task {
                // Give a normal grant time to arrive before suggesting something is off.
                try? await Task.sleep(for: OnboardingView.staleHelpDelay)
                withAnimation(.smooth) { showStaleHelp = true }
            }
            .frame(maxWidth: 460)
            .glassPanel()
        }
    }

    private var verify: some View {
        page(granted ? "You’re all set" : "Access isn’t on yet", granted ? "\(Branding.name) can now arrange your windows." : "It can take a few seconds to register. If it still doesn’t, quit and reopen \(Branding.name).") {
            VStack(spacing: 16) {
                Image(systemName: granted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(granted ? Color.green : Color.orange)
                    .symbolEffect(.bounce, value: granted)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityLabel(granted ? "Access granted" : "Access not granted")
                if !granted {
                    HStack {
                        Button("Check Again") { model.permission.refresh() }.glassButton()
                        Button("Open Settings") { model.permission.openSystemSettings() }.glassButton()
                    }
                    StaleGrantHelp()
                    Text("You can continue, but nothing is arranged until access is granted.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 460)
            .glassPanel()
        }
    }

    private var layouts: some View {
        page("Pick how windows share the screen", "Grid favours your main window. Columns shares the width equally.") {
            HStack(spacing: 18) {
                layoutCard(.grid, offset: 0)
                layoutCard(.columns, offset: 2)
            }
            Text("Extra windows can stack in the last tile or stay floating. Drop a window on another tile to swap them.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func layoutCard(_ kind: LayoutKind, offset: Int) -> some View {
        VStack(spacing: 8) {
            TilingDemo(kind: kind, autoplay: true, startOffset: offset)
            Text(kind.title).font(.headline)
        }
        .padding(12)
        .frame(maxWidth: 260)
        .glassPanel()
    }

    private func control<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            content().labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var choose: some View {
        let settings = model.settings
        return page("Make it yours", "You can change all of this later in Settings.") {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    control("Layout") {
                        Picker("Layout", selection: settings.binding(for: nil, \.layout)) {
                            ForEach(LayoutKind.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    control("Windows per display") {
                        Picker("Windows per display", selection: settings.binding(for: nil, \.maxWindows)) {
                            ForEach(1...LayoutDefaults.maxWindowsPerDisplay, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    control("When there are more windows") {
                        Picker("When there are more windows", selection: settings.binding(for: nil, \.overflow)) {
                            ForEach(OverflowPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                }
                .padding(20)
                .frame(width: 320)
                .glassPanel()
                TilingDemo(kind: settings.configuration.defaultDisplay.layout, count: settings.configuration.defaultDisplay.maxWindows)
                    .padding(12)
                    .frame(maxWidth: 240)
                    .glassPanel()
            }
        }
    }

    private var arrange: some View {
        let tiled = model.ui.tiledCounts.values.reduce(0, +)
        return page("Ready when you are", "Nothing has moved yet. Arrange your open windows now, or finish and \(Branding.name) will tile them as they open and close.") {
            VStack(spacing: 14) {
                Button {
                    model.settings.update { $0.hasCompletedOnboarding = true; $0.isTilingEnabled = true }
                    model.coordinator.arrangeNow()
                    withAnimation(.smooth) { hasArranged = true }
                } label: {
                    Label("Arrange My Windows Now", systemImage: "sparkles").padding(.horizontal, 8)
                }
                .glassButton(prominent: true)
                .controlSize(.large)
                .disabled(!granted)
                if !granted {
                    Text("Grant Accessibility access first.").font(.callout).foregroundStyle(.secondary)
                } else if hasArranged {
                    Label(tiled > 0 ? "Arranged \(tiled) window\(tiled == 1 ? "" : "s")." : "No tileable windows are open right now.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                    Text("Undo anytime: menu bar → Restore Previous Arrangement.").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(26)
            .frame(maxWidth: 460)
            .glassPanel()
        }
    }
}
