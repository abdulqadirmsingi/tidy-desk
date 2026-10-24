import SwiftUI

@main
struct TidyDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent().environment(delegate.model)
        } label: {
            MenuBarIcon().environment(delegate.model)
        }
        .menuBarExtraStyle(.menu)
    }
}
