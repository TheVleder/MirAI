import SwiftUI

/// Model download screen with HuggingFace model ID input, progress, speed, and management.
struct DownloadView: View {

    @Environment(ModelDownloader.self) private var downloader

    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.02, green: 0.02, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Floating orbs
            floatingOrbs

            VStack(spacing: 32) {
                Spacer()

                // Logo
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("MirAI")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("On‑Device Voice AI")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                }

                // Model selector card
                modelSelectorCard

                // Download progress or button
                downloadSection

                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .alert("Error", isPresented: Binding(
            get: { downloader.showError },
            set: { downloader.showError = $0 }
        )) {
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
            Text("This will delete the downloaded model and free up storage space.")
        }
    }

    // MARK: - Model Selector

    private var modelSelectorCard: some View {
        @Bindable var downloader = downloader

        return VStack(spacing: 14) {
            HStack {
                Image(systemName: "cube.box")
                    .foregroundColor(.cyan)
                Text("HuggingFace Model ID")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
            }

            TextField("mlx-community/model-name", text: $downloader.modelID)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
                .padding(14)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            HStack {
                Button {
                    downloader.restoreDefault()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Default")
                    }
                    .font(.caption)
                    .foregroundColor(.cyan.opacity(0.8))
                }

                Spacer()

                if downloader.downloadedModelID != nil {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Delete Model")
                        }
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.7))
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Download Section

    private var downloadSection: some View {
        VStack(spacing: 16) {
            switch downloader.state {
            case .idle:
                downloadButton("Download Model", icon: "arrow.down.circle.fill")

            case .downloading(let progress):
                VStack(spacing: 10) {
                    ProgressView(value: progress)
                        .tint(.cyan)
                        .scaleEffect(y: 2)

                    HStack {
                        Text(downloader.progressText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))

                        Spacer()

                        Text(downloader.downloadSpeed)
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .foregroundColor(.cyan)

                        Spacer()

                        Text("\(Int(progress * 100))%")
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

            case .completed:
                downloadButton("Model Ready ✓", icon: "checkmark.circle.fill", color: .green)

            case .failed:
                VStack(spacing: 10) {
                    downloadButton("Retry Download", icon: "arrow.clockwise.circle.fill", color: .orange)
                }
            }
        }
    }

    private func downloadButton(_ title: String, icon: String, color: Color = .cyan) -> some View {
        Button {
            Task { await downloader.downloadModel() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .foregroundColor(color == .green ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [color.opacity(0.8), color.opacity(0.5)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: color.opacity(0.3), radius: 12, y: 6)
        }
        .disabled(downloader.state != .idle && downloader.state != .failed(message: ""))
    }

    // MARK: - Floating Orbs

    private var floatingOrbs: some View {
        ZStack {
            Circle()
                .fill(Color.cyan.opacity(0.08))
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .offset(x: -80, y: -200)

            Circle()
                .fill(Color.blue.opacity(0.06))
                .frame(width: 250, height: 250)
                .blur(radius: 70)
                .offset(x: 100, y: 150)

            Circle()
                .fill(Color.purple.opacity(0.05))
                .frame(width: 180, height: 180)
                .blur(radius: 50)
                .offset(x: -60, y: 300)
        }
    }
}
