import Testing

@testable import TidyDeskCore

@Suite("Tiling status")
struct TilingStatusTests {
    private func resolve(
        permission: Bool = true, asleep: Bool = false, stage: Bool = false, enabled: Bool = true, onboarded: Bool = true
    ) -> TilingStatus {
        TilingStatus.resolve(
            permissionGranted: permission, isAsleep: asleep, stageManagerOn: stage, tilingEnabled: enabled,
            onboardingComplete: onboarded)
    }

    @Test func activeWhenEverythingIsInOrder() { #expect(resolve() == .active) }

    @Test func stageManagerPausesTilingEvenWhenEnabled() { #expect(resolve(stage: true) == .stageManagerOn) }

    @Test func tilingResumesWhenStageManagerTurnsOff() {
        #expect(resolve(stage: true) == .stageManagerOn)
        #expect(resolve(stage: false) == .active)
    }

    @Test func userPauseAndMissingOnboardingPause() {
        #expect(resolve(enabled: false) == .pausedByUser)
        #expect(resolve(onboarded: false) == .pausedByUser)
    }

    @Test func missingPermissionOutranksEverything() {
        #expect(resolve(permission: false, asleep: true, stage: true, enabled: false) == .needsPermission)
    }

    @Test func sleepOutranksStageManager() { #expect(resolve(asleep: true, stage: true) == .asleep) }

    @Test func stageManagerOutranksUserPause() { #expect(resolve(stage: true, enabled: false) == .stageManagerOn) }
}
