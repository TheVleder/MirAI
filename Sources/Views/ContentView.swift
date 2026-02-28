import SwiftUI

/// Root router view: shows DownloadView if model isn't ready, ChatView otherwise.
struct ContentView: View {

    @Environment(ModelDownloader.self) private var downloader

    var body: some View {
        Group {
            if downloader.isModelReady {
                ChatView()
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
