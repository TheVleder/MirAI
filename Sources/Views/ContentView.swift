import SwiftUI

/// Root router: Onboarding -> Download -> ConversationList -> Chat
struct ContentView: View {

    @Environment(ModelDownloader.self) private var downloader
    @State private var isOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    var body: some View {
        Group {
            if !isOnboarded {
                OnboardingView(isOnboarded: $isOnboarded)
                    .transition(.opacity)
            } else if downloader.isModelReady {
                ConversationListView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                DownloadView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isOnboarded)
        .animation(.easeInOut(duration: 0.5), value: downloader.isModelReady)
        .task {
            await downloader.checkExistingModel()
        }
    }
}
