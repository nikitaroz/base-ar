import SwiftUI

private enum RootPhase {
    case welcome
    case hub
}

enum HubRoute: Hashable, Identifiable {
    var id: Self { self }
    case guide
    case home
    case meter
    case breaker
    case placement
    case review
}

struct ContentView: View {
    @State private var phase: RootPhase = .welcome
    @State private var store: SurveyStore?
    @State private var path = NavigationPath()
    @State private var startError: String?

    var body: some View {
        Group {
            switch phase {
            case .welcome:
                WelcomeView {
                    beginSurvey()
                }
                .transition(.opacity)
            case .hub:
                if let store {
                    hubStack(store: store)
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: phase)
        .alert("Could not start the survey", isPresented: startErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(startError ?? "")
        }
    }

    @ViewBuilder
    private func hubStack(store: SurveyStore) -> some View {
        NavigationStack(path: $path) {
            SimplifiedSurveyFlow(store: store) { route in
                path.append(route)
            }
            .navigationDestination(for: HubRoute.self) { route in
                switch route {
                case .guide:
                    SimplifiedSurveyFlow(store: store) { path.append($0) }
                case .home:
                    HomeInformationView(store: store)
                case .meter:
                    ElectricalCaptureView(store: store, focus: .meter)
                case .breaker:
                    ElectricalCaptureView(store: store, focus: .breaker)
                case .placement:
                    PlacementARView(store: store) {
                        path.append(HubRoute.review)
                    }
                case .review:
                    ReviewView(
                        store: store,
                        onEdit: { editFromReview($0) },
                        onStartOver: { resetToWelcome() }
                    )
                }
            }
        }
    }

    private func beginSurvey() {
        do {
            store = try SurveyStore(propertyIdentifier: "", resumeDraft: true)
            path = NavigationPath()
            withAnimation(.easeInOut(duration: 0.35)) {
                phase = .hub
            }
        } catch {
            startError = error.localizedDescription
        }
    }

    private func editFromReview(_ route: HubRoute) {
        if route == .guide {
            path = NavigationPath()
            return
        }
        path.append(route)
    }

    private func resetToWelcome() {
        path = NavigationPath()
        store?.discardSavedSurvey()
        store = nil
        withAnimation(.easeInOut(duration: 0.35)) {
            phase = .welcome
        }
    }

    private var startErrorPresented: Binding<Bool> {
        Binding(
            get: { startError != nil },
            set: { if !$0 { startError = nil } }
        )
    }
}

// MARK: - Welcome

private struct WelcomeView: View {
    var onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 56)
                    Image(systemName: "bolt.house.fill")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                    Text("Base Site Survey")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Fill out your info, then scan your meter and equipment with your camera.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Prototype only. Results need engineer review.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 48)
                    Button(action: onContinue) {
                        Text(SurveyStore.hasSavedDraft ? "Continue" : "Get Started")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Hub

private struct SurveyHubView: View {
    var store: SurveyStore
    var onOpen: (HubRoute) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Site survey")
                    .font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(completedSectionCount) of 4 sections complete")
                        .font(.headline)
                    ProgressView(value: Double(completedSectionCount), total: 4)
                    Text("Complete these in any order. Your answers save as you go.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    hubTile(
                        title: "Home and personal info",
                        subtitle: "Name, address, and home setup",
                        symbol: "house.fill",
                        progress: homeProgress,
                        route: .home
                    )
                    hubTile(
                        title: "Electrical meter",
                        subtitle: "A photo and the meter number",
                        symbol: "gauge.with.dots.needle.33percent",
                        progress: meterProgress,
                        route: .meter
                    )
                    hubTile(
                        title: "Breaker box",
                        subtitle: "A photo and the breaker size",
                        symbol: "bolt.fill",
                        progress: breakerProgress,
                        route: .breaker
                    )
                    hubTile(
                        title: "Site measurements",
                        subtitle: "Find the meter and panel, then step back.",
                        symbol: "arkit",
                        progress: placementProgress,
                        route: .placement
                    )
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
    }

    private var homeProgress: StepProgress {
        let session = store.session
        let electrical = session.electrical
        // The location fix arrives on its own, so it does not count as the user finishing this step.
        return progress(for: [
            filled(session.contactName),
            filled(session.email),
            filled(session.phone),
            filled(session.propertyIdentifier),
            session.homeownership != nil,
            electrical.hasSolar != nil,
            electrical.hasPortableGenerator != nil,
            electrical.hasStandbyGenerator != nil,
            electrical.hasExistingWholeHomeBattery != nil,
            electrical.plannedBatteryCount != nil
        ])
    }

    private var meterProgress: StepProgress {
        progress(for: [
            store.session.electrical.meterPhotoFilename != nil,
            filled(store.session.electrical.meterNumber ?? "")
        ])
    }

    private var breakerProgress: StepProgress {
        progress(for: [
            store.session.electrical.breakerPhotoFilename != nil,
            store.session.electrical.mainBreakerAmperage != nil
        ])
    }

    private var placementProgress: StepProgress {
        let placement = store.session.placement
        let liveScene = store.placementController?.scene
        return progress(for: [
            placement.meterMarked || liveScene?.meterPosition != nil || liveScene?.meterWallPosition != nil,
            placement.panelMarked || liveScene?.panelPosition != nil || liveScene?.panelWallPosition != nil
        ])
    }

    private var sectionProgress: [StepProgress] {
        [homeProgress, meterProgress, breakerProgress, placementProgress]
    }

    private var completedSectionCount: Int {
        sectionProgress.filter(\.isComplete).count
    }

    private var allSectionsComplete: Bool { completedSectionCount == sectionProgress.count }

    private func filled(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func progress(for answers: [Bool]) -> StepProgress {
        StepProgress(answered: answers.filter { $0 }.count, total: answers.count)
    }

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
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(progress.title). \(subtitle).")
        .accessibilityHint("Opens \(title).")
    }
}

// MARK: - Home and personal info

private struct StepProgress: Equatable {
    var answered: Int
    var total: Int

    var isComplete: Bool { total > 0 && answered == total }

    var title: String {
        if answered == 0 { return "Not started" }
        if isComplete { return "Complete" }
        return "\(answered) of \(total) answered"
    }
}

private enum AnswerChoice: String, CaseIterable, Identifiable {
    case no
    case yes

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

private enum OwnershipChoice: String, CaseIterable, Identifiable {
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

private enum BatteryCountChoice: String, CaseIterable, Identifiable {
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

struct HomeInformationView: View {
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
                Text("Changing your address will clear your location and previous scans.")
                    .font(.footnote).foregroundStyle(.secondary)
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
                Text("Base serves homeowners. Renters join the waitlist.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Energy setup") {
                RadioChoice(title: "Solar", selection: solarBinding) { $0.title }
                RadioChoice(title: "Portable generator", selection: portableGeneratorBinding) { $0.title }
                RadioChoice(title: "Standby generator", selection: standbyGeneratorBinding) { $0.title }
                RadioChoice(title: "Existing battery", selection: existingBatteryBinding) { $0.title }
                RadioChoice(title: "Base batteries wanted", selection: batteryCountBinding) { $0.title }
                Text("Some equipment may affect installation. We'll record what you have.")
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
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

private struct RadioChoice<Choice: Hashable & Identifiable>: View where Choice: CaseIterable, Choice.AllCases: RandomAccessCollection {
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
                    .frame(minHeight: 32)
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
