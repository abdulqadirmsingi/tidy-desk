import SwiftUI

/// Shown when access looks switched on in System Settings but the app is still not trusted, which
/// happens when the grant belongs to a different build of the app.
struct StaleGrantHelp: View {
    @Environment(AppModel.self) private var model
    @State private var isWorking = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Already switched on, but still waiting?", systemImage: "info.circle")
                .font(.callout.weight(.semibold))
            Text("macOS ties the permission to this exact build of \(Branding.name). If an older copy was allowed before, the switch can look on without applying. Reset it, then switch it on again.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button {
                    isWorking = true
                    Task {
                        failed = !(await model.permission.resetStaleGrant())
                        isWorking = false
                    }
                } label: {
                    Text(isWorking ? "Resetting…" : "Reset Permission and Try Again")
                }
                .glassButton()
                .disabled(isWorking)
                if failed {
                    Text("Couldn’t reset automatically. Remove \(Branding.name) from the list with the − button, then add it back.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
