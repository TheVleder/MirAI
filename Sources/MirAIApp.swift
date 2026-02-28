import SwiftUI

@main
struct MirAIApp: App {

    @State private var downloader = ModelDownloader()
    @State private var llmManager = LLMManager()
    @State private var audioManager = AudioManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(downloader)
                .environment(llmManager)
                .environment(audioManager)
                .preferredColorScheme(.dark)
        }
    }
}
