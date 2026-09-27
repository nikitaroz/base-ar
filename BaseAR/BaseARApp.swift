import SwiftUI

@main
struct BaseARApp: App {
    init() {
        // Before the first survey: pick the unfinished survey to resume and clear out empty and old folders.
        SurveyLibrary.prepareForLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
