import SwiftUI

/// Root router: Download → ConversationList → Chat
struct ContentView: View {

    @Environment(ModelDownloader.self) private var downloader

    var body: some View {
        Group {
            if downloader.isModelReady {
                ConversationListView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                DownloadView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: downloader.isModelReady)
        .task {
            await downloader.checkExistingModel()
        }
    }
}
