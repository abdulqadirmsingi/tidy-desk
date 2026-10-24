import Foundation
import Testing

@testable import TidyDeskCore

@Suite("Menu bar symbol and Dock setting")
struct MenuBarSymbolTests {
    @Test func everyStatusHasADistinctlyReadableSymbol() {
        func symbol(_ status: TilingStatus, special: Bool = false, style: MenuBarIconStyle = .outline) -> String {
            MenuBarSymbol.name(status: status, isSpecialModeActive: special, style: style)
        }
        #expect(symbol(.active) == "rectangle.split.2x2")
        #expect(symbol(.active, style: .filled) == "rectangle.split.2x2.fill")
        #expect(symbol(.active, special: true) == "scope")
        #expect(symbol(.needsPermission) == "exclamationmark.triangle")
        for paused in [TilingStatus.pausedByUser, .stageManagerOn, .asleep] { #expect(symbol(paused) == "pause.rectangle") }
    }

    @Test func attentionStatesNeverLookLikeTheActiveIcon() {
        let active = MenuBarSymbol.name(status: .active, isSpecialModeActive: false, style: .outline)
        for status in [TilingStatus.needsPermission, .pausedByUser, .stageManagerOn, .asleep] {
            #expect(MenuBarSymbol.name(status: status, isSpecialModeActive: false, style: .outline) != active)
        }
    }

    @Test func dockIconDefaultsOffAndSurvivesOlderFiles() throws {
        #expect(!Configuration().showInDock)
        let old = try ConfigurationMigration.decode(Data(#"{"schemaVersion":1}"#.utf8))
        #expect(!old.showInDock)
        var config = Configuration()
        config.showInDock = true
        let data = try JSONEncoder().encode(config)
        #expect(try ConfigurationMigration.decode(data).showInDock)
    }
}
