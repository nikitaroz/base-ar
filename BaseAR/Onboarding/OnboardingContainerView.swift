import SwiftUI

/// Shared UI timing so the step animation and the focus delay stay coupled.
enum OnboardingUI {
    static let stepAnimation: Animation = .spring(response: 0.5, dampingFraction: 0.85)
    static let focusDelay: TimeInterval = 0.35
}

/// Six-screen wizard that opens a new survey (the first one, and each one after Start over) and collects the
/// essential Home Info fields. Writes through the same `SurveyStore` setters the Home Info form uses, so skipped
/// fields stay empty and are still fillable in step 1 later.
struct OnboardingContainerView: View {
    var store: SurveyStore
    var onFinish: () -> Void

    @State private var step: OnboardingStep = .intro

    private var progress: Double {
        Double(step.index + 1) / Double(OnboardingStep.total)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
        .animation(OnboardingUI.stepAnimation, value: step)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(Color.accentColor)
                .frame(height: 4)
                .animation(.easeOut(duration: 0.35), value: progress)
            if step != .done && step != .email {
                Button("Skip") { onFinish() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Skip onboarding")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intro:
            OnboardingIntroPage(onNext: advance)
                .transition(pageTransition)
        case .name:
            OnboardingNamePage(store: store, onNext: advance, onSkip: onFinish)
                .transition(pageTransition)
        case .email:
            OnboardingEmailPage(store: store, onNext: advance)
                .transition(pageTransition)
        case .address:
            OnboardingAddressPage(store: store, onNext: advance, onSkip: onFinish)
                .transition(pageTransition)
        case .ownership:
            OnboardingOwnershipPage(store: store, onNext: advance, onSkip: onFinish)
                .transition(pageTransition)
        case .batteryCount:
            OnboardingBatteryCountPage(store: store, onNext: advance, onSkip: onFinish)
                .transition(pageTransition)
        case .gasMeter:
            OnboardingGasMeterPage(store: store, onNext: advance, onSkip: onFinish)
                .transition(pageTransition)
        case .done:
            OnboardingDonePage(onContinue: onFinish)
                .transition(pageTransition)
        }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private func advance() {
        if let next = step.next {
            step = next
        } else {
            onFinish()
        }
    }
}

enum OnboardingStep: Int, CaseIterable, Equatable {
    case intro
    case name
    case email
    case address
    case ownership
    case batteryCount
    case gasMeter
    case done

    static let total = OnboardingStep.allCases.count

    var index: Int { rawValue }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }
}

#Preview {
    if let store = try? SurveyStore(propertyIdentifier: "preview") {
        OnboardingContainerView(store: store, onFinish: {})
    } else {
        Text("Preview unavailable")
    }
}
