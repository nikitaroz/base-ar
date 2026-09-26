import SwiftUI

private enum RootPhase {
    case splash
    case intro
    case hub
}

enum HubRoute: Hashable {
    case home
    case meter
    case breaker
    case placement
    case review
}

struct ContentView: View {
    @State private var phase: RootPhase = .splash
    @State private var store: SurveyStore?
    @State private var path = NavigationPath()
    @State private var startError: String?

    var body: some View {
        Group {
            switch phase {
            case .splash:
                SplashView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        phase = .intro
                    }
                }
                .transition(.opacity)
            case .intro:
                IntroView {
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
            SurveyHubView(store: store) { route in
                path.append(route)
            }
            .navigationDestination(for: HubRoute.self) { route in
                switch route {
                case .home:
                    HomeInformationView(store: store) {
                        path.removeLast()
                    }
                case .meter:
                    ElectricalCaptureView(store: store, focus: .meter) {
                        path.removeLast()
                    }
                case .breaker:
                    ElectricalCaptureView(store: store, focus: .breaker) {
                        path.removeLast()
                    }
                case .placement:
                    PlacementARView(store: store) {
                        path.append(HubRoute.review)
                    }
                case .review:
                    ReviewView(store: store) {
                        resetToSplash()
                    }
                }
            }
        }
    }

    private func beginSurvey() {
        do {
            store = try SurveyStore(propertyIdentifier: "")
            path = NavigationPath()
            withAnimation(.easeInOut(duration: 0.35)) {
                phase = .hub
            }
        } catch {
            startError = error.localizedDescription
        }
    }

    private func resetToSplash() {
        path = NavigationPath()
        store?.discardSavedSurvey()
        store = nil
        withAnimation(.easeInOut(duration: 0.35)) {
            phase = .splash
        }
    }

    private var startErrorPresented: Binding<Bool> {
        Binding(
            get: { startError != nil },
            set: { if !$0 { startError = nil } }
        )
    }
}

// MARK: - Splash

private struct SplashView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "bolt.house.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.primary)
            Text("Base Site Survey")
                .font(.largeTitle.bold())
            Text("A first look at your home for a Base Power battery")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Intro

private struct IntroView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Let’s get your battery placement")
                .font(.largeTitle.bold())
            Text("Take photos of your home, meter, and breaker, then see where a Base Core could sit outside. An engineer may still ask for more photos.")
                .font(.body)
                .foregroundStyle(.secondary)
            Text(SurveySession.prototypeDisclaimer)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
                Text("You can do these in any order.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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
                        title: "Battery placement",
                        subtitle: "See where it could go",
                        symbol: "arkit",
                        progress: placementProgress,
                        route: .placement
                    )
                }

                Button {
                    onOpen(.review)
                } label: {
                    Text("Review survey")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Text(SurveySession.prototypeDisclaimer)
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
        if store.session.placement.batteryPlaced { return .done }
        if store.placementController?.scene.hasPlacedContent == true { return .inProgress }
        return .notStarted
    }

    private func filled(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func progress(for answers: [Bool]) -> StepProgress {
        let filledCount = answers.filter { $0 }.count
        if filledCount == 0 { return .notStarted }
        if filledCount == answers.count { return .done }
        return .inProgress
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
                if progress == .done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
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

private enum StepProgress: Equatable {
    case notStarted
    case inProgress
    case done

    var title: String {
        switch self {
        case .notStarted: "Not started"
        case .inProgress: "In progress"
        case .done: "Done"
        }
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

private struct HomeInformationView: View {
    var store: SurveyStore
    var onDone: () -> Void

    @State private var addressCompleter = AddressCompleter()
    @FocusState private var fieldIsFocused: Bool

    var body: some View {
        Form {
            Section("Personal") {
                TextField("Name", text: contactNameBinding)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .focused($fieldIsFocused)
                TextField("Email", text: emailBinding)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($fieldIsFocused)
                TextField("Phone", text: phoneBinding)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .focused($fieldIsFocused)
            }

            Section("Address") {
                TextField("Property address or identifier", text: addressBinding)
                    .textContentType(.fullStreetAddress)
                    .textInputAutocapitalization(.words)
                    .focused($fieldIsFocused)
                    .onChange(of: store.session.propertyIdentifier) { _, newValue in
                        addressCompleter.updateQuery(newValue)
                    }
                ForEach(addressCompleter.suggestions) { suggestion in
                    Button {
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
                    }
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
                Text("An existing standby generator or another whole-home battery is a filter Base uses before installation. This survey records the answer.")
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
                    Text(store.locationStatusMessage ?? "Waiting for a property fix, or location was not available.")
                        .foregroundStyle(.secondary)
                    Button("Try again") {
                        store.retryPropertyLocation()
                    }
                }
                Text(SurveySession.locationDisclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Done") {
                    fieldIsFocused = false
                    onDone()
                }
                Text(SurveySession.prototypeDisclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Home and personal info")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldIsFocused = false }
            }
        }
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
            ForEach(Array(Choice.allCases)) { choice in
                let selected = selection == choice
                Button {
                    selection = choice
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        Text(label(choice))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), \(label(choice))")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}
