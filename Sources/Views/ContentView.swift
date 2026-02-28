import SwiftUI

/// Root router: Onboarding -> Loading -> Download -> ConversationList -> Chat
struct ContentView: View {

    @Environment(ModelDownloader.self) private var downloader
    @State private var isOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @State private var isCheckingModel = true

    var body: some View {
        Group {
            if !isOnboarded {
                OnboardingView(isOnboarded: $isOnboarded)
                    .transition(.opacity)
            } else if isCheckingModel {
                // Show loading screen while checking if model exists
                loadingScreen
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
        .animation(.easeInOut(duration: 0.5), value: isCheckingModel)
        .animation(.easeInOut(duration: 0.5), value: downloader.isModelReady)
        .task {
            if downloader.downloadedModelID != nil {
                isCheckingModel = true
                await downloader.checkExistingModel()
                isCheckingModel = false
            } else {
                isCheckingModel = false
            }
        }
    }

    // MARK: - Loading Screen

    private var loadingScreen: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.12)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse, isActive: true)

                Text("MirAI")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Loading model…")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))

                ProgressView()
                    .tint(.cyan)
                    .scaleEffect(1.2)
                    .padding(.top, 8)
            }
        }
    }
}
