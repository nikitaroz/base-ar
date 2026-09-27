import SwiftUI

private enum RootPhase {
    case splash
    case welcome
    case onboarding
    case survey
}

/// Where Review's rows and edit buttons send the user. The shell switches steps for `.home`, `.placement`, and
/// `.review`; only `.electrical` is pushed.
enum HubRoute: Hashable {
    case home
    case electrical
    case placement
    case review
}

/// The survey's three steps, in order. The step indicator opens any of them at any time.
enum SurveyStep: Int, CaseIterable, Identifiable {
    case home
    case scan
    case review

    var id: Int { rawValue }

    /// The step indicator's short label.
    var title: String {
        switch self {
        case .home: "Home"
        case .scan: "Scan"
        case .review: "Review"
        }
    }

    /// The step's full name, for VoiceOver and copy.
    var longTitle: String {
        switch self {
        case .home: "Home Info"
        case .scan: "Live Survey"
        case .review: "Review and export"
        }
    }
}

/// Screens pushed on top of a step. The steps themselves are switched, not pushed.
private enum SurveyPush: Hashable {
    case electrical
}

struct ContentView: View {
    @State private var phase: RootPhase = .splash
    @State private var store: SurveyStore?
    @State private var step: SurveyStep = .home
    /// Where the Live Survey's left-edge swipe goes back to: Review when it was opened from Review, else Home Info.
    @State private var scanReturnStep: SurveyStep = .home
    @State private var path = NavigationPath()
    @State private var startError: String?
    @Namespace private var brandNamespace
    /// Set when the wizard finishes or is skipped. Start over clears it, so each new survey begins with the wizard.
    @AppStorage("hasSeenHomeInfoOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            switch phase {
            case .splash:
                SplashView(namespace: brandNamespace)
            case .welcome:
                WelcomeView(namespace: brandNamespace) {
                    beginSurvey()
                }
            case .onboarding:
                if let store {
                    OnboardingContainerView(store: store) {
                        finishOnboarding()
                    }
                    .transition(.opacity)
                }
            case .survey:
                if let store {
                    surveyShell(store: store)
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: phase)
        .alert("Could not start the survey", isPresented: startErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(startError ?? "")
        }
        .task {
            guard phase == .splash else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                phase = .welcome
            }
        }
    }

    // MARK: Survey shell

    /// Home Info → Live Survey → Review and export. The Live Survey is only the camera and its two lines, so the
    /// step indicator and the navigation bar are hidden there.
    private func surveyShell(store: SurveyStore) -> some View {
        NavigationStack(path: $path) {
            stepScreen(store: store)
                .animation(.easeInOut(duration: 0.25), value: step)
                .navigationDestination(for: SurveyPush.self) { push in
                    switch push {
                    case .electrical:
                        ElectricalCaptureView(store: store)
                    }
                }
        }
    }

    @ViewBuilder
    private func stepScreen(store: SurveyStore) -> some View {
        switch step {
        case .home:
            HomeInformationView(store: store)
                .safeAreaInset(edge: .top, spacing: 0) {
                    stepIndicator(store: store)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PinnedStepButton(title: "Next: Live Survey", systemImage: "camera.viewfinder") {
                        go(to: .scan)
                    }
                }
                .transition(.opacity)
        case .scan:
            PlacementARView(
                store: store,
                // The left-edge swipe (and VoiceOver's escape) goes back to the step the Live Survey was opened from.
                onExit: { leaveLiveSurvey() },
                onContinue: { go(to: .review) },
                onReturnToSurvey: { leaveLiveSurvey() }
            )
            .toolbar(.hidden, for: .navigationBar)
            .transition(.opacity)
        case .review:
            ReviewView(
                store: store,
                onEdit: { open($0) },
                onStartOver: { resetToWelcome() }
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                stepIndicator(store: store)
            }
            .transition(.opacity)
        }
    }

    private func stepIndicator(store: SurveyStore) -> some View {
        StepIndicator(current: step, isComplete: { store.isComplete($0) }) { target in
            go(to: target)
        }
    }

    /// Switches to a step and drops anything pushed on top of the current one.
    private func go(to target: SurveyStep) {
        path = NavigationPath()
        guard target != step else { return }
        if target == .scan { scanReturnStep = step == .review ? .review : .home }
        step = target
    }

    /// Leaving the Live Survey goes back where it was opened from: Review (a finished scan opened again) or Home
    /// Info. The Live Survey's exit gesture calls this.
    private func leaveLiveSurvey() {
        go(to: scanReturnStep)
    }

    /// Review's rows: Home Info and the Live Survey are steps; Electrical is pushed over Review.
    private func open(_ route: HubRoute) {
        switch route {
        case .home:
            go(to: .home)
        case .placement:
            go(to: .scan)
        case .review:
            go(to: .review)
        case .electrical:
            path.append(SurveyPush.electrical)
        }
    }

    private func beginSurvey() {
        do {
            store = try SurveyStore(propertyIdentifier: "")
            path = NavigationPath()
            step = .home
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                phase = hasSeenOnboarding ? .survey : .onboarding
            }
        } catch {
            startError = error.localizedDescription
        }
    }

    private func finishOnboarding() {
        hasSeenOnboarding = true
        path = NavigationPath()
        step = .home
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            phase = .survey
        }
    }

    /// Start over: the survey is deleted, and the next one begins with the wizard again.
    /// The files are deleted after the switch to Welcome has drawn, so a large scan folder does not hold the tap.
    private func resetToWelcome() {
        path = NavigationPath()
        let discarded = store
        store = nil
        step = .home
        hasSeenOnboarding = false
        withAnimation(.easeInOut(duration: 0.35)) {
            phase = .welcome
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            discarded?.discardSavedSurvey()
        }
    }

    private var startErrorPresented: Binding<Bool> {
        Binding(
            get: { startError != nil },
            set: { if !$0 { startError = nil } }
        )
    }
}

// MARK: - Step indicator

/// Home · Scan · Review. Each segment opens its step, in any order. A checkmark means every item that step asks
/// for is answered. It never says a check passed: Review's tone does that.
struct StepIndicator: View {
    var current: SurveyStep
    var isComplete: (SurveyStep) -> Bool
    var onSelect: (SurveyStep) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SurveyStep.allCases) { step in
                segment(step)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func segment(_ step: SurveyStep) -> some View {
        let selected = step == current
        let done = isComplete(step)
        return Button {
            onSelect(step)
        } label: {
            VStack(spacing: 6) {
                Capsule()
                    .fill(barColor(selected: selected, done: done))
                    .frame(height: 4)
                HStack(spacing: 5) {
                    Image(systemName: done ? "checkmark.circle.fill" : "\(step.rawValue + 1).circle")
                        .foregroundStyle(done || selected ? Color.accentColor : Color.secondary)
                    Text(step.title)
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                }
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .animation(.easeOut(duration: 0.25), value: done)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(SurveyStep.allCases.count), \(step.longTitle)")
        .accessibilityValue(done ? "Complete" : "Not complete")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func barColor(selected: Bool, done: Bool) -> Color {
        if selected { return .accentColor }
        return done ? Color.accentColor.opacity(0.4) : Color(.tertiarySystemFill)
    }
}

/// The one primary action pinned under a step, above the home indicator.
private struct PinnedStepButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

// MARK: - Splash

private struct SplashView: View {
    var namespace: Namespace.ID
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Image("BrandMark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 148, height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: Color.accentColor.opacity(0.35), radius: 24, y: 8)
                .matchedGeometryEffect(id: "brand", in: namespace)
                .scaleEffect(appeared ? 1.0 : 0.7)
                .opacity(appeared ? 1.0 : 0.0)
                .onAppear {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                        appeared = true
                    }
                }
                .accessibilityLabel("Base Site Survey")
        }
    }
}

// MARK: - Welcome

private struct WelcomeView: View {
    var namespace: Namespace.ID
    var onContinue: () -> Void
    @State private var contentAppeared = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 56)
                    Image("BrandMark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .matchedGeometryEffect(id: "brand", in: namespace)
                        .accessibilityHidden(true)
                    Group {
                        Text("Base Site Survey")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Three steps to see where a Base battery could sit outside your home.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 14) {
                            WelcomeStepRow(
                                number: 1,
                                title: "Home Info",
                                detail: "A few questions about you and your home."
                            )
                            WelcomeStepRow(
                                number: 2,
                                title: "Live Survey",
                                detail: "Walk outside with the camera. It looks for the electric meter and panel and tells you what to do next."
                            )
                            WelcomeStepRow(
                                number: 3,
                                title: "Review and export",
                                detail: "Check what was captured, fix anything missing, and share it."
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Text(SurveySession.prototypeDisclaimer)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 12)
                    Spacer(minLength: 48)
                    Button(action: onContinue) {
                        Text("Start survey")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .opacity(contentAppeared ? 1 : 0)
                }
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            withAnimation(.easeOut(duration: 0.45).delay(0.15)) {
                contentAppeared = true
            }
        }
    }
}

private struct WelcomeStepRow: View {
    var number: Int
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "\(number).circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(title). \(detail)")
    }
}

// MARK: - Hub (retired)

// The three-step shell replaced this hub: nothing shows it now. Kept for reference, and it reads the same
// progress helpers as the step indicator.

private struct SurveyHubView: View {
    var store: SurveyStore
    var onOpen: (HubRoute) -> Void
    @State private var tilesAppeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Site survey")
                    .font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(completedSectionCount) of 3 sections complete")
                        .font(.headline)
                    ProgressView(value: Double(completedSectionCount), total: 3)
                        .animation(.easeOut(duration: 0.4), value: completedSectionCount)
                    Text("Complete these in any order.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    animatedTile(index: 0) {
                        hubTile(
                            title: "Home and personal info",
                            subtitle: "Name, address, and home setup",
                            symbol: "house.fill",
                            progress: homeProgress,
                            route: .home
                        )
                    }
                    animatedTile(index: 1) {
                        hubTile(
                            title: "Electrical",
                            subtitle: "Meter photo, meter number, and breaker size",
                            symbol: "bolt.fill",
                            progress: electricalProgress,
                            route: .electrical
                        )
                    }
                    animatedTile(index: 2) {
                        hubTile(
                            title: "Site measurements",
                            subtitle: "Find the meter and panel, show the gas meter, then step back.",
                            symbol: "arkit",
                            progress: placementProgress,
                            route: .placement
                        )
                    }
                }

                Button {
                    onOpen(.review)
                } label: {
                    Text(allSectionsComplete ? "Review survey" : "Review missing items")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Preliminary survey only. An engineer must confirm the site.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !tilesAppeared else { return }
            tilesAppeared = true
        }
    }

    @ViewBuilder
    private func animatedTile<Content: View>(index: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(tilesAppeared ? 1 : 0)
            .offset(y: tilesAppeared ? 0 : 16)
            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.08 * Double(index)), value: tilesAppeared)
    }

    private var homeProgress: StepProgress { store.homeProgress }

    private var electricalProgress: StepProgress { store.electricalProgress }

    private var placementProgress: StepProgress { store.placementProgress }

    private var sectionProgress: [StepProgress] {
        [homeProgress, electricalProgress, placementProgress]
    }

    private var completedSectionCount: Int {
        sectionProgress.filter(\.isComplete).count
    }

    private var allSectionsComplete: Bool { completedSectionCount == sectionProgress.count }

    private func hubTile(
        title: String,
        subtitle: String,
        symbol: String,
        progress: StepProgress,
        route: HubRoute
    ) -> some View {
        Button {
            onOpen(route)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 32, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(progress.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                if progress.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Complete")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(progress.title). \(subtitle).")
        .accessibilityHint("Opens \(title).")
    }
}

// MARK: - Progress

/// Cards that need obvious press feedback since .plain otherwise strips all affordance.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// How many of a section's items are answered. Completion only: it never says whether a check passes.
struct StepProgress: Equatable {
    var answered: Int
    var total: Int

    init(answered: Int, total: Int) {
        self.answered = answered
        self.total = total
    }

    init(_ answers: [Bool]) {
        self.init(answered: answers.filter { $0 }.count, total: answers.count)
    }

    var isComplete: Bool { total > 0 && answered == total }

    var title: String {
        if answered == 0 { return "Not started" }
        if isComplete { return "Complete" }
        return "\(answered) of \(total) answered"
    }
}

/// Progress for the step indicator (and the retired hub). The live scene counts too, so a mark made on the scan
/// shows before the scan is saved.
extension SurveyStore {
    /// Home Info. The location fix arrives on its own, so it does not count as the user finishing this step.
    var homeProgress: StepProgress {
        let electrical = session.electrical
        return StepProgress([
            Self.filled(session.contactName),
            Self.filled(session.email),
            Self.filled(session.phone),
            Self.filled(session.propertyIdentifier),
            session.homeownership != nil,
            electrical.hasSolar != nil,
            electrical.hasPortableGenerator != nil,
            electrical.hasStandbyGenerator != nil,
            electrical.hasExistingWholeHomeBattery != nil,
            electrical.plannedBatteryCount != nil,
            session.gasMeterQuestionAnswered
        ])
    }

    /// The meter photo and number, the main breaker, and the panel's bus rating when solar or two batteries need it.
    var electricalProgress: StepProgress {
        StepProgress(electricalAnswers)
    }

    /// The hub's site-measurements tile: battery, electric meter, and gas meter (or the answer that there is none).
    var placementProgress: StepProgress {
        let placement = session.placement
        let liveScene = placementController?.scene
        return StepProgress([
            placement.batteryPlaced || liveScene?.batteryPosition != nil,
            placement.meterMarked || liveMeterMarked,
            gasMeterResolved
        ])
    }

    /// The Live Survey: it finds the meter and panel, reads the meter number and breaker, is shown the gas meter
    /// (unless Home Info says there is none), and suggests the battery spot at the finish. A finish that found no
    /// spot still answers that item: Review says why, and an engineer chooses one.
    var scanProgress: StepProgress {
        let placement = session.placement
        let liveScene = placementController?.scene
        return StepProgress(electricalAnswers + [
            placement.meterMarked || liveMeterMarked,
            placement.panelMarked || livePanelMarked,
            gasMeterResolved,
            placement.batteryPlaced || liveScene?.batteryPosition != nil || placement.batterySpot != nil
        ])
    }

    /// Nothing is missing and every required check passed, measured or attested: Review says "Ready to share".
    var isReadyToShare: Bool {
        missingItems.isEmpty && (session.placementTone == .clear || session.placementTone == .attested)
            && SiteCheck.of(session) != .noClearSpot
    }

    /// The same list Review's "What's missing" counts, computed fresh from the session.
    var missingItems: [MissingItem] { MissingInformation.items(for: session) }

    /// A step shows done only when Review lists nothing for it: Home Info's items for Home, and the Live Survey's
    /// items plus the numbers it reads for Scan.
    func isComplete(_ step: SurveyStep) -> Bool {
        let missing = missingItems
        switch step {
        case .home: return !missing.contains { $0.step == .home }
        case .scan: return !missing.contains { $0.step == .electrical || $0.step == .scan }
        case .review: return isReadyToShare
        }
    }

    /// The scan holds a meter lock, saved or not.
    var liveMeterMarked: Bool {
        guard let scene = placementController?.scene else { return false }
        return scene.meterPosition != nil || scene.meterWallPosition != nil
    }

    /// The scan holds a panel lock, saved or not.
    var livePanelMarked: Bool {
        guard let scene = placementController?.scene else { return false }
        return scene.panelPosition != nil || scene.panelWallPosition != nil
    }

    private var gasMeterResolved: Bool {
        session.placement.gasMeterMarked || placementController?.scene.gasMeterPosition != nil || gasMeterNotVisible
    }

    private var electricalAnswers: [Bool] {
        let electrical = session.electrical
        var answers = [
            electrical.meterPhotoFilename != nil,
            Self.filled(electrical.meterNumber ?? ""),
            electrical.mainBreakerAmperage != nil
        ]
        // Only solar or two batteries need the panel's bus rating.
        if electrical.needsPanelBusRating {
            answers.append(electrical.panelBusRatingAmps != nil)
        }
        return answers
    }

    private static func filled(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Home and personal info

/// Yes first, like the gas question's Yes / No / Not sure, so every Home Info answer reads in the same order.
private enum AnswerChoice: String, CaseIterable, Identifiable {
    case yes
    case no

    var id: String { rawValue }

    var title: String {
        switch self {
        case .no: "No"
        case .yes: "Yes"
        }
    }

    var value: Bool {
        switch self {
        case .no: false
        case .yes: true
        }
    }

    init?(value: Bool?) {
        switch value {
        case false: self = .no
        case true: self = .yes
        case nil: return nil
        }
    }
}

extension GasMeterAnswer: Identifiable {
    var id: String { rawValue }

    var title: String {
        switch self {
        case .yes: "Yes"
        case .no: "No"
        case .notSure: "Not sure"
        }
    }
}

enum OwnershipChoice: String, CaseIterable, Identifiable {
    case own
    case rent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .own: "Own"
        case .rent: "Rent"
        }
    }

    var value: Homeownership {
        switch self {
        case .own: .own
        case .rent: .rent
        }
    }

    init?(value: Homeownership?) {
        switch value {
        case .own: self = .own
        case .rent: self = .rent
        case nil: return nil
        }
    }
}

enum BatteryCountChoice: String, CaseIterable, Identifiable {
    case one
    case two

    var id: String { rawValue }

    var title: String {
        switch self {
        case .one: "1"
        case .two: "2"
        }
    }

    var value: Int {
        switch self {
        case .one: 1
        case .two: 2
        }
    }

    init?(count: Int?) {
        switch count {
        case 1: self = .one
        case 2: self = .two
        default: return nil
        }
    }
}

private struct HomeInformationView: View {
    var store: SurveyStore

    @State private var addressCompleter = AddressCompleter()
    @FocusState private var focusedField: HomeField?

    private enum HomeField: Hashable {
        case name, email, phone, address
    }

    var body: some View {
        Form {
            Section("Personal") {
                LabeledContent("Name") {
                    TextField("Required", text: contactNameBinding)
                        .multilineTextAlignment(.trailing)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                }
                LabeledContent("Email") {
                    TextField("Required", text: emailBinding)
                        .multilineTextAlignment(.trailing)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                }
                if shouldShowEmailWarning {
                    Label("Enter an email address such as name@example.com.", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                LabeledContent("Phone") {
                    TextField("Required", text: phoneBinding)
                        .multilineTextAlignment(.trailing)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: .phone)
                }
                if shouldShowPhoneWarning {
                    Label("Enter a complete phone number.", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("Address") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Property address or identifier")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Required", text: addressBinding)
                        .textContentType(.fullStreetAddress)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .address)
                        .onChange(of: store.session.propertyIdentifier) { _, newValue in
                            addressCompleter.updateQuery(newValue)
                        }
                }
                ForEach(addressCompleter.suggestions) { suggestion in
                    Button {
                        focusedField = nil
                        let line = addressCompleter.accept(suggestion)
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section("Home") {
                RadioChoice(title: "Own or rent", selection: ownershipBinding) { $0.title }
                Text("Base currently serves homeowners. Renters are waitlisted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Energy setup") {
                RadioChoice(title: "Solar", selection: solarBinding) { $0.title }
                RadioChoice(title: "Portable generator", selection: portableGeneratorBinding) { $0.title }
                RadioChoice(title: "Whole-home standby generator", selection: standbyGeneratorBinding) { $0.title }
                RadioChoice(title: "Existing whole-home battery", selection: existingBatteryBinding) { $0.title }
                RadioChoice(title: "Planned Base batteries", selection: batteryCountBinding) { $0.title }
                BatteryCountDecisionCard(decision: BatteryCountDecision.make(
                    plannedCount: store.session.electrical.plannedBatteryCount,
                    hasSolar: store.session.electrical.hasSolar,
                    panelBusRatingAmps: store.session.electrical.panelBusRatingAmps,
                    propertyIdentifier: store.session.propertyIdentifier
                ))
                Text("An existing standby generator or another whole-home battery is a filter Base uses before installation. This survey records the answer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Gas") {
                RadioChoice(title: "Gas meter outside", selection: gasMeterBinding) { $0.title }
                Text("The battery must sit at least 3 ft from a gas meter. If you have one, the Live Survey asks you to point the camera at it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Location") {
                if let fix = store.session.propertyLocation {
                    PropertyLocationMap(fix: fix)
                    LabeledContent("Captured", value: fix.timestamp.formatted(date: .abbreviated, time: .standard))
                    LabeledContent(
                        "Accuracy",
                        value: String(format: "%.1f m", fix.horizontalAccuracyMeters)
                    )
                } else {
                    Text(store.locationStatusMessage ?? "Use this iPhone’s location to place the property on the map.")
                        .foregroundStyle(.secondary)
                    if store.isRequestingPropertyLocation {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Getting this iPhone’s location…")
                        }
                        .foregroundStyle(.secondary)
                    }
                    Button {
                        focusedField = nil
                        store.requestPropertyLocation()
                    } label: {
                        Label(
                            store.locationStatusMessage == nil ? "Use current location" : "Try location again",
                            systemImage: "location.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.isRequestingPropertyLocation)
                }
                Text(SurveySession.locationDisclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        }
        .navigationTitle("Home and personal info")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }

    private var shouldShowEmailWarning: Bool {
        let value = store.session.email.trimmingCharacters(in: .whitespacesAndNewlines)
        return focusedField != .email && !value.isEmpty && (!value.contains("@") || !value.contains("."))
    }

    private var shouldShowPhoneWarning: Bool {
        let digits = store.session.phone.filter(\.isNumber)
        return focusedField != .phone && !store.session.phone.isEmpty && digits.count < 7
    }

    private var contactNameBinding: Binding<String> {
        Binding(
            get: { store.session.contactName },
            set: { store.setContactName($0) }
        )
    }

    private var emailBinding: Binding<String> {
        Binding(
            get: { store.session.email },
            set: { store.setEmail($0) }
        )
    }

    private var phoneBinding: Binding<String> {
        Binding(
            get: { store.session.phone },
            set: { store.setPhone($0) }
        )
    }

    private var addressBinding: Binding<String> {
        Binding(
            get: { store.session.propertyIdentifier },
            set: { store.setPropertyIdentifier($0) }
        )
    }

    private var ownershipBinding: Binding<OwnershipChoice?> {
        Binding(
            get: { OwnershipChoice(value: store.session.homeownership) },
            set: { store.setHomeownership($0?.value) }
        )
    }

    /// "No" is the homeowner's statement: the store records it as attested and the Live Survey skips the gas step.
    private var gasMeterBinding: Binding<GasMeterAnswer?> {
        Binding(
            get: { store.session.electrical.gasMeterAnswer },
            set: { store.setGasMeterAnswer($0) }
        )
    }

    private var solarBinding: Binding<AnswerChoice?> {
        Binding(
            get: { AnswerChoice(value: store.session.electrical.hasSolar) },
            set: { store.setHasSolar($0?.value) }
        )
    }

    private var portableGeneratorBinding: Binding<AnswerChoice?> {
        Binding(
            get: { AnswerChoice(value: store.session.electrical.hasPortableGenerator) },
            set: { store.setHasPortableGenerator($0?.value) }
        )
    }

    private var standbyGeneratorBinding: Binding<AnswerChoice?> {
        Binding(
            get: { AnswerChoice(value: store.session.electrical.hasStandbyGenerator) },
            set: { store.setHasStandbyGenerator($0?.value) }
        )
    }

    private var existingBatteryBinding: Binding<AnswerChoice?> {
        Binding(
            get: { AnswerChoice(value: store.session.electrical.hasExistingWholeHomeBattery) },
            set: { store.setHasExistingWholeHomeBattery($0?.value) }
        )
    }

    private var batteryCountBinding: Binding<BatteryCountChoice?> {
        Binding(
            get: { BatteryCountChoice(count: store.session.electrical.plannedBatteryCount) },
            set: { store.setPlannedBatteryCount($0?.value) }
        )
    }
}

struct RadioChoice<Choice: Hashable & Identifiable>: View where Choice: CaseIterable, Choice.AllCases: RandomAccessCollection {
    var title: String
    @Binding var selection: Choice?
    var label: (Choice) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            choiceButtons
        }
        .padding(.vertical, 6)
    }

    private var choiceButtons: some View {
        HStack(spacing: 24) {
            ForEach(Array(Choice.allCases)) { choice in
                let selected = selection == choice
                Button {
                    selection = choice
                } label: {
                    Label {
                        Text(label(choice))
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), \(label(choice))")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

#Preview {
    ContentView()
}
