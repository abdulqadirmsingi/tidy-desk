import SwiftUI
import TidyDeskCore

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable {
        case welcome, permission, grant, verify, layouts, choose, arrange
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(32)
            Divider()
            HStack {
                ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                    .frame(width: 120)
                    .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                Spacer()
                if step != .welcome { Button("Back") { move(-1) } }
                Button(step == .arrange ? "Finish" : "Continue") {
                    if step == .arrange { model.completeOnboarding() } else { move(1) }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 640, height: 480)
    }

    private func move(_ delta: Int) {
        step = Step(rawValue: min(max(step.rawValue + delta, 0), Step.allCases.count - 1)) ?? step
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            page("rectangle.split.2x2", "Welcome to \(Branding.name)",
                 "\(Branding.name) lives in your menu bar and keeps your windows neatly arranged. When windows open, close or move, the rest adjust automatically. You stay in control: pause or undo at any time.")
        case .permission:
            page("hand.raised", "Why Accessibility access?",
                 "To move and resize other apps’ windows, macOS requires your permission. \(Branding.name) uses it only to place windows. It never records your screen, reads document contents, or sends anything over the network.")
        case .grant:
            VStack(alignment: .leading, spacing: 16) {
                header("gearshape", "Grant access")
                Text("Click the button, then switch \(Branding.name) on in Privacy & Security → Accessibility.")
                Button("Open Accessibility Settings") {
                    model.permission.requestPrompt()
                    model.permission.openSystemSettings()
                }
            }
        case .verify:
            VStack(alignment: .leading, spacing: 16) {
                header(model.permission.isGranted ? "checkmark.circle" : "exclamationmark.triangle", "Checking access")
                if model.permission.isGranted {
                    Text("Access granted. You’re all set.").foregroundStyle(.green)
                } else {
                    Text("Access isn’t granted yet. It can take a few seconds to register; if it still doesn’t, quit and reopen \(Branding.name). You can continue now, but nothing is arranged until access is granted.")
                    Button("Check Again") { model.permission.refresh() }
                }
            }
        case .layouts:
            page("square.grid.2x2", "Grid, Columns and stacks",
                 "Grid puts the first window on the left and splits the rest around it. Columns shares the width equally. Choose 1–4 windows per display; extra windows can stack in the last tile or stay floating. Control+Option shortcuts swap, move and resize tiles — see Settings → Shortcuts. Drag a window onto another tile to swap them.")
        case .choose:
            VStack(alignment: .leading, spacing: 16) {
                header("slider.horizontal.3", "Choose your starting point")
                Form { LayoutControls(display: nil) }.formStyle(.grouped)
                LayoutPreview(settings: model.settings.configuration.defaultDisplay)
            }
        case .arrange:
            VStack(alignment: .leading, spacing: 16) {
                header("sparkles", "Ready when you are")
                Text("Nothing has been moved yet. Arrange your open windows now, or finish and let \(Branding.name) tile windows as they change. You can always restore the previous arrangement from the menu bar.")
                Button("Arrange My Windows Now") {
                    model.settings.update { $0.hasCompletedOnboarding = true; $0.isTilingEnabled = true }
                    model.coordinator.arrangeNow()
                }
                .disabled(!model.permission.isGranted)
                if !model.permission.isGranted {
                    Text("Grant Accessibility access first (step 3).").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func header(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol).font(.title2.weight(.semibold))
    }

    private func page(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(symbol, title)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
