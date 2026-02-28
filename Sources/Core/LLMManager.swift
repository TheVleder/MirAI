import Foundation
import Observation
import MLXLLM
import MLXLMCommon
import MLX

/// Manages the MLX LLM model lifecycle: loading, multi-turn chat, and streaming text generation.
/// Dynamically loads whichever model the user has downloaded.
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

    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?

    // MARK: - System Prompt

    private let systemPrompt = """
        You are MirAI, a friendly and concise voice AI assistant. \
        Keep your responses short and conversational — typically 1-3 sentences. \
        You are running locally on the user's iPhone. \
        Respond naturally as if having a spoken conversation.
        """

    // MARK: - Model Loading

    /// Load the model dynamically based on the given model ID
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

            // Create a chat session for multi-turn conversation
            chatSession = ChatSession(container, systemPrompt: systemPrompt)

            state = .ready
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    // MARK: - Text Generation

    /// Generate a response for the given user prompt
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

    /// Reset the conversation history
    func resetConversation() {
        guard let container = modelContainer else { return }
        chatSession = ChatSession(container, systemPrompt: systemPrompt)
        currentResponse = ""
    }

    /// Unload the current model from memory
    func unloadModel() {
        modelContainer = nil
        chatSession = nil
        loadedModelName = ""
        currentResponse = ""
        state = .idle
    }
}
