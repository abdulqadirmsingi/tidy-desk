import Testing

@testable import TidyDeskCore

@Suite("Onboarding flow")
struct OnboardingFlowTests {
    @Test func fullTourHasSevenStepsInOrder() {
        #expect(OnboardingFlow.steps(permissionGranted: false) == OnboardingStep.allCases)
    }

    @Test func grantedAccessSkipsPermissionExplanationAndRequest() {
        #expect(OnboardingFlow.steps(permissionGranted: true) == [.welcome, .verify, .layouts, .choose, .arrange])
    }

    @Test func advancingWalksForwardAndStopsAtTheEnd() {
        var flow = OnboardingFlow()
        for _ in 0..<20 { flow.advance(permissionGranted: false) }
        #expect(flow.current == .arrange)
        #expect(flow.isLast(permissionGranted: false))
        #expect(flow.movedForward)
    }

    @Test func goingBackStopsAtTheStartAndFlipsDirection() {
        var flow = OnboardingFlow()
        flow.advance(permissionGranted: false)
        flow.goBack(permissionGranted: false)
        #expect(flow.current == .welcome && !flow.movedForward)
        flow.goBack(permissionGranted: false)
        #expect(flow.current == .welcome && flow.isFirst(permissionGranted: false))
    }

    @Test func grantingAccessMidTourMovesOnInsteadOfStrandingTheUser() {
        var flow = OnboardingFlow()
        flow.jump(to: .grant)
        flow.advance(permissionGranted: true)
        #expect(flow.current == .verify)
    }

    @Test func goingBackFromVerifyAfterGrantSkipsPermissionSteps() {
        var flow = OnboardingFlow()
        flow.jump(to: .verify)
        flow.goBack(permissionGranted: true)
        #expect(flow.current == .welcome)
    }

    @Test func progressCountsOnlyVisibleSteps() {
        var flow = OnboardingFlow()
        #expect(flow.progress(permissionGranted: false) == (1, 7))
        flow.jump(to: .layouts)
        #expect(flow.progress(permissionGranted: false) == (5, 7))
        #expect(flow.progress(permissionGranted: true) == (3, 5))
    }

    @Test func progressIsSensibleWhenCurrentStepWasHidden() {
        var flow = OnboardingFlow()
        flow.jump(to: .grant)
        let progress = flow.progress(permissionGranted: true)
        #expect(progress.position >= 1 && progress.position <= progress.total)
    }
}
