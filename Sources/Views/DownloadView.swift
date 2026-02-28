import SwiftUI

/// Model download screen with dynamic model selection, glassmorphism design, and progress tracking.
struct DownloadView: View {

    @Environment(ModelDownloader.self) private var downloader

    @State private var showDeleteConfirmation = false

    var body: some View {
        @Bindable var downloader = downloader

        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.05, blue: 0.2),
                    Color(red: 0.05, green: 0.1, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Floating orbs
            FloatingOrbs()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 20)

                    // App icon & branding
                    branding

                    // Model selector card
                    modelSelectorCard

                    // Download state
                    downloadStateView

                    // Delete model button (only if a model was downloaded)
                    if downloader.downloadedModelID != nil {
                        deleteModelButton
                    }

                    Spacer().frame(height: 12)

                    // Privacy note
                    Label("100% private. Runs entirely on your device.", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
            }
        }
        .alert("Error", isPresented: $downloader.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloader.errorMessage ?? "Unknown error")
        }
        .alert("Delete Model", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                downloader.deleteCurrentModel()
            }
        } message: {
            Text("This will delete the downloaded model and free storage space. You can download another model afterwards.")
        }
    }

    // MARK: - Branding

    private var branding: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.cyan.opacity(0.3),
                                Color.purple.opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 140, height: 140)

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 70))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text("MirAI")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("Voice Intelligence, On-Device")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Model Selector Card

    private var modelSelectorCard: some View {
        @Bindable var downloader = downloader

        return VStack(spacing: 16) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .font(.title3)
                    .foregroundColor(.cyan)

                Text("Model Selection")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: "lock.shield.fill")
                    .font(.callout)
                    .foregroundColor(.green.opacity(0.7))
            }

            // Model ID input
            VStack(alignment: .leading, spacing: 8) {
                Text("HuggingFace Model ID")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))

                TextField("mlx-community/model-name", text: $downloader.modelID)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Text("Enter any MLX-compatible model from huggingface.co (e.g. mlx-community/...)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }

            // Restore default button
            if downloader.modelID != ModelDownloader.defaultModelID {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        downloader.restoreDefault()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption)
                        Text("Restore default (Qwen 2.5 1.5B 4-bit)")
                            .font(.caption)
                    }
                    .foregroundColor(.cyan.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Download State

    @ViewBuilder
    private var downloadStateView: some View {
        switch downloader.state {
        case .idle:
            downloadButton
        case .downloading(let progress):
            downloadingProgress(progress: progress)
        case .completed:
            completedBadge
        case .failed(let message):
            failedState(message: message)
        }
    }

    // MARK: - Download Button

    private var downloadButton: some View {
        Button {
            Task {
                await downloader.downloadModel()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download Model")
                        .font(.headline)
                    Text(downloader.modelDisplayName)
                        .font(.caption)
                        .opacity(0.7)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [
                        Color.cyan.opacity(0.8),
                        Color.purple.opacity(0.8)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .cyan.opacity(0.3), radius: 20, y: 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress

    private func downloadingProgress(progress: Double) -> some View {
        VStack(spacing: 16) {
            // Model name being downloaded
            Text(downloader.modelDisplayName)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.1))
                        .frame(height: 8)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.cyan, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: max(0, geometry.size.width * CGFloat(progress)),
                            height: 8
                        )
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 8)

            // Stats
            HStack {
                Text(downloader.progressText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.cyan)
                    .contentTransition(.numericText(value: progress))
                    .animation(.easeInOut, value: progress)
            }

            HStack(spacing: 8) {
                ProgressView()
                    .tint(.white.opacity(0.6))
                    .scaleEffect(0.8)
                Text("Downloading model weights…")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Completed

    private var completedBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Model ready!")
                    .font(.headline)
                    .foregroundColor(.white)
                Text(downloader.modelDisplayName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Failed

    private func failedState(message: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Download failed")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            Text(message)
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineLimit(4)

            Button("Retry") {
                Task { await downloader.downloadModel() }
            }
            .font(.subheadline.bold())
            .foregroundColor(.cyan)
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Delete Model

    private var deleteModelButton: some View {
        Button {
            showDeleteConfirmation = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.subheadline)
                Text("Delete model & free space")
                    .font(.subheadline)
            }
            .foregroundColor(.red.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Floating Background Orbs

struct FloatingOrbs: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.cyan.opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: animate ? 50 : -50, y: animate ? -100 : -150)

            Circle()
                .fill(Color.purple.opacity(0.1))
                .frame(width: 250, height: 250)
                .blur(radius: 70)
                .offset(x: animate ? -70 : 70, y: animate ? 200 : 150)

            Circle()
                .fill(Color.blue.opacity(0.06))
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .offset(x: animate ? 100 : -20, y: animate ? 50 : 100)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}
