import SwiftUI

// MARK: - Shared layout

/// Common layout for every onboarding page: hero illustration, headline, subtitle, controls, primary button, optional skip.
private struct OnboardingPageLayout<Controls: View>: View {
    let illustration: OnboardingIllustration
    let title: String
    let subtitle: String?
    let primaryTitle: String
    let primaryEnabled: Bool
    let onPrimary: () -> Void
    let onSkip: (() -> Void)?
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 24)
                    illustration.view
                        .frame(width: 220, height: 220)
                        .accessibilityHidden(true)
                    VStack(spacing: 12) {
                        Text(title)
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 8)
                    controls()
                        .padding(.top, 4)
                    Spacer(minLength: 8)
                    VStack(spacing: 10) {
                        Button(action: onPrimary) {
                            Text(primaryTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!primaryEnabled)
                        if let onSkip {
                            Button("Skip this", action: onSkip)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(minHeight: 44)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }
}

/// An onboarding hero image. Prefers a bundled asset; falls back to an SF Symbol if the asset is missing so
/// the flow keeps working before the generated PNGs land.
struct OnboardingIllustration {
    let assetName: String
    let fallbackSymbol: String

    @ViewBuilder var view: some View {
        if UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: fallbackSymbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color.accentColor)
                .padding(24)
        }
    }
}

// MARK: - Screen 1: Intro

struct OnboardingIntroPage: View {
    var onNext: () -> Void

    var body: some View {
        OnboardingPageLayout(
            illustration: OnboardingIllustration(assetName: "OnboardingIntro", fallbackSymbol: "checklist"),
            title: "Let’s get you set up",
            subtitle: "A few quick questions so we can tailor the survey to your home. You can skip anything and finish it later.",
            primaryTitle: "Get started",
            primaryEnabled: true,
            onPrimary: onNext,
            onSkip: nil,
            controls: { EmptyView() }
        )
    }
}

// MARK: - Screen 2: Name

struct OnboardingNamePage: View {
    var store: SurveyStore
    var onNext: () -> Void
    var onSkip: () -> Void

    @State private var name: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        OnboardingPageLayout(
            illustration: OnboardingIllustration(assetName: "OnboardingName", fallbackSymbol: "person.crop.circle"),
            title: "What should we call you?",
            subtitle: "Just your name so the survey has a contact on it.",
            primaryTitle: "Next",
            primaryEnabled: !trimmed.isEmpty,
            onPrimary: {
                store.setContactName(trimmed)
                onNext()
            },
            onSkip: onSkip
        ) {
            TextField("Your name", text: $name)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.next)
                .onSubmit {
                    guard !trimmed.isEmpty else { return }
                    store.setContactName(trimmed)
                    onNext()
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .font(.title3)
        }
        .onAppear {
            if name.isEmpty { name = store.session.contactName }
            DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingUI.focusDelay) { focused = true }
        }
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Screen 3: Address

struct OnboardingAddressPage: View {
    var store: SurveyStore
    var onNext: () -> Void
    var onSkip: () -> Void

    @State private var address: String = ""
    @State private var completer = AddressCompleter()
    @FocusState private var focused: Bool

    var body: some View {
        OnboardingPageLayout(
            illustration: OnboardingIllustration(assetName: "OnboardingAddress", fallbackSymbol: "mappin.and.ellipse"),
            title: "Where’s the property?",
            subtitle: "The street address where the battery would go. Start typing and pick a suggestion.",
            primaryTitle: "Next",
            primaryEnabled: !trimmed.isEmpty,
            onPrimary: {
                store.setPropertyIdentifier(trimmed)
                onNext()
            },
            onSkip: onSkip
        ) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("123 Main St, Austin, TX", text: $address)
                    .textContentType(.fullStreetAddress)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .padding(14)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .font(.title3)
                    .onChange(of: address) { _, value in
                        completer.updateQuery(value)
                    }
                if !completer.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(completer.suggestions.prefix(4)) { suggestion in
                            Button {
                                focused = false
                                let line = completer.accept(suggestion)
                                address = line
                                store.setPropertyIdentifier(line)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                        .foregroundStyle(.primary)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if suggestion.id != completer.suggestions.prefix(4).last?.id {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .onAppear {
            if address.isEmpty { address = store.session.propertyIdentifier }
            DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingUI.focusDelay) { focused = true }
        }
    }

    private var trimmed: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Screen 4: Ownership

struct OnboardingOwnershipPage: View {
    var store: SurveyStore
    var onNext: () -> Void
    var onSkip: () -> Void

    @State private var selection: OwnershipChoice?

    var body: some View {
        OnboardingPageLayout(
            illustration: OnboardingIllustration(assetName: "OnboardingOwnership", fallbackSymbol: "key.fill"),
            title: "Do you own or rent?",
            subtitle: "Base installs for homeowners today. Renters are recorded on a waitlist.",
            primaryTitle: "Next",
            primaryEnabled: selection != nil,
            onPrimary: {
                store.setHomeownership(selection?.value)
                onNext()
            },
            onSkip: onSkip
        ) {
            RadioChoice(title: "", selection: $selection) { $0.title }
                .padding(.horizontal, 4)
        }
        .onAppear {
            if selection == nil { selection = OwnershipChoice(value: store.session.homeownership) }
        }
    }
}

// MARK: - Screen 5: Battery count

struct OnboardingBatteryCountPage: View {
    var store: SurveyStore
    var onNext: () -> Void
    var onSkip: () -> Void

    @State private var selection: BatteryCountChoice?

    var body: some View {
        OnboardingPageLayout(
            illustration: OnboardingIllustration(assetName: "OnboardingBatteries", fallbackSymbol: "bolt.batteryblock.fill"),
            title: "How many Base batteries?",
            subtitle: "Most homes go with one. Two is common for larger houses or full backup during outages.",
            primaryTitle: "Next",
            primaryEnabled: selection != nil,
            onPrimary: {
                store.setPlannedBatteryCount(selection?.value)
                onNext()
            },
            onSkip: onSkip
        ) {
            RadioChoice(title: "", selection: $selection) { $0.title }
                .padding(.horizontal, 4)
        }
        .onAppear {
            if selection == nil { selection = BatteryCountChoice(count: store.session.electrical.plannedBatteryCount) }
        }
    }
}

// MARK: - Screen 6: Done

struct OnboardingDonePage: View {
    var onContinue: () -> Void

    var body: some View {
        OnboardingPageLayout(
            illustration: OnboardingIllustration(assetName: "OnboardingDone", fallbackSymbol: "checkmark.circle.fill"),
            title: "You’re all set",
            subtitle: "The Home tile is prefilled with what you shared. You can edit it anytime from the survey hub.",
            primaryTitle: "Continue to survey",
            primaryEnabled: true,
            onPrimary: onContinue,
            onSkip: nil,
            controls: { EmptyView() }
        )
    }
}
