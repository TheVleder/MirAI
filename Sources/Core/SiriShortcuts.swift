import AppIntents

/// Siri Shortcut: "Ask MirAI" — opens the app and starts listening.
struct AskMirAIIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask MirAI"
    static var description = IntentDescription("Start a voice conversation with MirAI")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Opening the app is handled by openAppWhenRun.
        // The app will detect this via UserDefaults flag and auto-start listening.
        UserDefaults.standard.set(true, forKey: "siriLaunchListening")
        return .result()
    }
}

/// Register shortcuts with the system.
struct MirAIShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskMirAIIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Talk to \(.applicationName)",
                "Hey \(.applicationName)"
            ],
            shortTitle: "Ask MirAI",
            systemImageName: "mic.fill"
        )
    }
}
