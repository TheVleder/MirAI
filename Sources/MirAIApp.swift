import SwiftUI
import SwiftData

@main
struct MirAIApp: App {

    @State private var downloader = ModelDownloader()
    @State private var llmManager = LLMManager()
    @State private var audioManager = AudioManager()
    @State private var conversationManager = ConversationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(downloader)
                .environment(llmManager)
                .environment(audioManager)
                .environment(conversationManager)
                .preferredColorScheme(.dark)
                .onAppear {
                    if let context = try? ModelContext(
                        ModelContainer(for: Conversation.self, Message.self)
                    ) {
                        conversationManager.setContext(context)
                    }
                }
        }
        .modelContainer(for: [Conversation.self, Message.self, CustomPersonality.self])
    }
}
