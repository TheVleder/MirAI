import Foundation
import Observation
import MLXLLM
import MLXLMCommon
import MLX

/// Manages the MLX LLM model lifecycle with personality support.
@Observable
@MainActor
final class LLMManager {

    // MARK: - State

    enum LLMState: Equatable {
        case idle
        case loading
        case ready
        case generating
        case error(message: String)
    }

    var state: LLMState = .idle
    var currentResponse: String = ""
    var loadedModelName: String = ""

    /// Current personality
    var activePersonality: Personality = Personality.find("friend") {
        didSet {
            UserDefaults.standard.set(activePersonality.id, forKey: "activePersonalityID")
            // Reset session with new personality prompt
            if modelContainer != nil {
                resetConversation()
            }
        }
    }

    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?

    // MARK: - Init

    init() {
        let savedID = UserDefaults.standard.string(forKey: "activePersonalityID") ?? "friend"
        activePersonality = Personality.find(savedID)
    }

    // MARK: - Model Loading

    func loadModel(modelID: String) async {
        guard state != .loading && state != .generating else { return }
        state = .loading

        let config = ModelConfiguration(
            id: modelID,
            defaultPrompt: "You are a helpful AI assistant."
        )

        do {
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { progress in
                _ = progress
            }
            modelContainer = container
            loadedModelName = modelID.components(separatedBy: "/").last ?? modelID

            chatSession = ChatSession(container, instructions: activePersonality.systemPrompt)

            state = .ready
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    // MARK: - Text Generation

    func generate(prompt: String) async -> String {
        guard let session = chatSession else {
            state = .error(message: "Model not loaded")
            return "Error: Model not loaded."
        }

        state = .generating
        currentResponse = ""

        do {
            let response = try await session.respond(to: prompt)
            currentResponse = response
            state = .ready
            return response
        } catch {
            let errorMsg = "Generation error: \(error.localizedDescription)"
            state = .error(message: errorMsg)
            currentResponse = errorMsg
            return errorMsg
        }
    }

    /// Reset conversation with current personality
    func resetConversation() {
        guard let container = modelContainer else { return }
        chatSession = ChatSession(container, instructions: activePersonality.systemPrompt)
        currentResponse = ""
    }

    /// Switch personality and reset the session
    func switchPersonality(_ personality: Personality) {
        activePersonality = personality
    }

    func unloadModel() {
        modelContainer = nil
        chatSession = nil
        loadedModelName = ""
        currentResponse = ""
        state = .idle
    }
}
