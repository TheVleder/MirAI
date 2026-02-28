import Foundation
import Observation
import MLXLLM
import MLXLMCommon

/// Manages downloading LLM models from HuggingFace Hub via mlx-swift-lm.
/// Supports dynamic model selection — the user provides a HuggingFace model ID.
@Observable
@MainActor
final class ModelDownloader {

    // MARK: - Constants

    static let defaultModelID = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"

    // MARK: - State

    enum DownloadState: Equatable {
        case idle
        case downloading(progress: Double)
        case completed
        case failed(message: String)
    }

    var state: DownloadState = .idle
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var errorMessage: String? = nil
    var showError: Bool = false

    // Speed tracking
    private var lastSpeedCheckTime: Date = Date()
    private var lastSpeedCheckBytes: Int64 = 0

    /// Download speed formatted string
    var downloadSpeed: String {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSpeedCheckTime)
        guard elapsed > 0.5 else { return "Calculating…" }
        let bytesPerSec = Double(downloadedBytes - lastSpeedCheckBytes) / elapsed
        if bytesPerSec > 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_000_000)
        } else if bytesPerSec > 1_000 {
            return String(format: "%.0f KB/s", bytesPerSec / 1_000)
        }
        return "Calculating…"
    }

    /// The currently configured model ID (persisted via UserDefaults)
    var modelID: String {
        didSet {
            UserDefaults.standard.set(modelID, forKey: "selectedModelID")
        }
    }

    /// The model ID that was last successfully downloaded
    var downloadedModelID: String? {
        get { UserDefaults.standard.string(forKey: "downloadedModelID") }
        set { UserDefaults.standard.set(newValue, forKey: "downloadedModelID") }
    }

    /// Whether the model is already available (cached by the hub)
    var isModelReady: Bool {
        state == .completed
    }

    /// Formatted progress string ("650 MB / 1.1 GB")
    var progressText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let downloaded = formatter.string(fromByteCount: downloadedBytes)
        if totalBytes > 0 {
            let total = formatter.string(fromByteCount: totalBytes)
            return "\(downloaded) / \(total)"
        }
        return downloaded
    }

    /// Progress percentage 0.0 to 1.0
    var progressFraction: Double {
        if case .downloading(let progress) = state {
            return progress
        }
        return 0
    }

    /// The display name extracted from the model ID
    var modelDisplayName: String {
        modelID.components(separatedBy: "/").last ?? modelID
    }

    // MARK: - Init

    init() {
        self.modelID = UserDefaults.standard.string(forKey: "selectedModelID")
            ?? Self.defaultModelID
    }

    // MARK: - Configuration

    /// Build a ModelConfiguration from the current model ID
    private func currentConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            id: modelID,
            defaultPrompt: "You are a helpful AI assistant."
        )
    }

    // MARK: - Actions

    /// Restore the model ID to the default Qwen 2.5
    func restoreDefault() {
        modelID = Self.defaultModelID
    }

    /// Validate the model ID format
    func validateModelID() -> Bool {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        // Must be "org/model-name" format
        let parts = trimmed.components(separatedBy: "/")
        guard parts.count >= 2 else {
            showErrorAlert("Invalid model ID format. Use 'organization/model-name' (e.g. mlx-community/Qwen2.5-1.5B-Instruct-4bit).")
            return false
        }
        guard !parts[0].isEmpty, !parts[1].isEmpty else {
            showErrorAlert("Model ID cannot have empty organization or model name.")
            return false
        }
        return true
    }

    /// Check if the model is already cached and ready to use
    func checkExistingModel() async {
        guard downloadedModelID != nil else {
            state = .idle
            return
        }

        // Use the downloaded model ID for the check
        let config = ModelConfiguration(
            id: downloadedModelID!,
            defaultPrompt: "You are a helpful AI assistant."
        )

        do {
            let _ = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { progress in
                Task { @MainActor in
                    self.state = .downloading(progress: progress.fractionCompleted)
                    self.downloadedBytes = progress.completedUnitCount
                    self.totalBytes = progress.totalUnitCount
                }
            }
            // Sync the text field to the downloaded model
            modelID = downloadedModelID!
            state = .completed
        } catch {
            // Model not cached — stay idle
            downloadedModelID = nil
            state = .idle
        }
    }

    /// Download the model from HuggingFace Hub
    func downloadModel() async {
        guard validateModelID() else { return }

        let cleanID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        state = .downloading(progress: 0)
        downloadedBytes = 0
        totalBytes = 0
        lastSpeedCheckTime = Date()
        lastSpeedCheckBytes = 0

        let config = ModelConfiguration(
            id: cleanID,
            defaultPrompt: "You are a helpful AI assistant."
        )

        do {
            let _ = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { progress in
                Task { @MainActor in
                    self.state = .downloading(progress: progress.fractionCompleted)
                    self.downloadedBytes = progress.completedUnitCount
                    self.totalBytes = progress.totalUnitCount
                }
            }
            downloadedModelID = cleanID
            state = .completed
        } catch {
            state = .failed(message: error.localizedDescription)
            showErrorAlert("Download failed: \(error.localizedDescription)")
        }
    }

    /// Delete the currently downloaded model and free storage
    func deleteCurrentModel() {
        // Clear the hub cache for this model
        let cacheDirectories = [
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ]

        for baseDir in cacheDirectories.compactMap({ $0 }) {
            // MLX Swift LM caches models inside "huggingface" directory structure
            let hubDir = baseDir.appendingPathComponent("huggingface")
            if FileManager.default.fileExists(atPath: hubDir.path) {
                try? FileManager.default.removeItem(at: hubDir)
            }
        }

        downloadedModelID = nil
        state = .idle
    }

    // MARK: - Error Handling

    private func showErrorAlert(_ message: String) {
        errorMessage = message
        showError = true
    }
}
