import SwiftUI
import TidyDeskCore

struct OnboardingView: View {
    @Environment(AppModel.self) var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var flow = OnboardingFlow()
    @State var hasArranged = false

    init(startAt step: OnboardingStep = .welcome) {
        var flow = OnboardingFlow()
        flow.jump(to: step)
        _flow = State(initialValue: flow)
    }

    var granted: Bool { model.permission.isGranted }

    var body: some View {
        ZStack {
            AmbientGlassBackground()
            VStack(spacing: 0) {
                ZStack {
                    content(for: flow.current)
                        .id(flow.current)
                        .transition(slide)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 44)
                .padding(.top, 48)
                footer
            }
        }
        .frame(width: 700, height: 520)
        .onChange(of: granted) { _, nowGranted in
            // Don't strand the user on a "grant access" page once access has arrived.
            if nowGranted, flow.current == .permission || flow.current == .grant {
                move { flow.advance(permissionGranted: true) }
            }
        }
    }

    private var slide: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let enter: Edge = flow.movedForward ? .trailing : .leading
        let leave: Edge = flow.movedForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: enter).combined(with: .opacity), removal: .move(edge: leave).combined(with: .opacity))
    }

    func move(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.45)) { change() }
    }

    private var footer: some View {
        let steps = OnboardingFlow.steps(permissionGranted: granted)
        let progress = flow.progress(permissionGranted: granted)
        return HStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach(steps, id: \.self) { step in
                    Capsule()
                        .fill(step == flow.current ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: step == flow.current ? 22 : 7, height: 7)
                }
            }
            .animation(reduceMotion ? nil : .smooth, value: flow.current)
            .accessibilityElement()
            .accessibilityLabel("Step \(progress.position) of \(progress.total)")
            Spacer()
            if !flow.isFirst(permissionGranted: granted) {
                Button("Back") { move { flow.goBack(permissionGranted: granted) } }.glassButton()
            }
            if flow.isLast(permissionGranted: granted) {
                Button("Finish") { model.completeOnboarding() }.glassButton(prominent: true).keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { move { flow.advance(permissionGranted: granted) } }
                    .glassButton(prominent: true).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }
}
