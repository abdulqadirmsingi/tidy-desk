import SwiftUI

@main
struct TidyDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// The app has no standard scenes: the menu bar item and its panel are AppKit (StatusItemController),
    /// and Settings and the tour are opened on demand. This inert scene only satisfies `App`.
    var body: some Scene {
        MenuBarExtra("", isInserted: .constant(false)) { EmptyView() }
    }
}
