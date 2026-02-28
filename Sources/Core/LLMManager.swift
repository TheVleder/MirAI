import Foundation
import Observation
import MLXLLM
import MLXLMCommon
import MLX

/// Manages the MLX LLM model lifecycle with personality, language, and streaming support.
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
            if modelContainer != nil {
                resetConversation()
            }
        }
    }

    /// Current active language
    var activeLanguage: AppLanguage = AppLanguage.saved() {
        didSet {
            activeLanguage.save()
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
            chatSession = ChatSession(container, instructions: buildSystemPrompt())
            state = .ready
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    // MARK: - Full Generation (non-streaming)

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
            return handleError(error)
        }
    }

    // MARK: - Streaming Generation

    /// Generate with streaming — calls `onSentence` each time a full sentence is ready.
    /// This allows TTS to start speaking the first sentence immediately.
    func generateStreaming(prompt: String, onSentence: @escaping (String) -> Void) async -> String {
        guard let session = chatSession else {
            state = .error(message: "Model not loaded")
            return "Error: Model not loaded."
        }

        state = .generating
        currentResponse = ""

        var buffer = ""
        let sentenceEnders: CharacterSet = CharacterSet(charactersIn: ".!?\n")

        do {
            let response = try await session.respond(to: prompt) { partial in
                Task { @MainActor [weak self] in
                    self?.currentResponse += partial
                }

                buffer += partial

                // Check for sentence boundary
                while let range = buffer.rangeOfCharacter(from: sentenceEnders) {
                    let idx = buffer.index(after: range.lowerBound)
                    let sentence = String(buffer[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
                    buffer = String(buffer[idx...])

                    if !sentence.isEmpty {
                        onSentence(sentence)
                    }
                }

                return .more
            }

            // Speak any remaining buffered text
            let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                onSentence(remaining)
            }

            currentResponse = response
            state = .ready
            return response
        } catch {
            return handleError(error)
        }
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error) -> String {
        let desc = error.localizedDescription.lowercased()
        let errorMsg: String
        if desc.contains("memory") || desc.contains("malloc") || desc.contains("allocation") {
            errorMsg = "⚠️ Out of memory. Close other apps and try again, or use a smaller model."
        } else {
            errorMsg = "Error: \(error.localizedDescription)"
        }
        state = .error(message: errorMsg)
        currentResponse = errorMsg
        return errorMsg
    }

    // MARK: - System Prompt

    private func buildSystemPrompt() -> String {
        """
        \(activePersonality.systemPrompt)

        IMPORTANT RULES:
        - \(activeLanguage.llmInstruction)
        - ALWAYS stay in character as \(activePersonality.name).
        - Remember the ENTIRE conversation history and refer back to it when relevant.
        - Keep responses concise (1-4 sentences) unless the user asks for more detail.
        """
    }

    // MARK: - Conversation Management

    func resetConversation() {
        guard let container = modelContainer else { return }
        chatSession = ChatSession(container, instructions: buildSystemPrompt())
        currentResponse = ""
    }

    func startSession(withHistory messages: [(role: String, content: String)] = []) {
        guard let container = modelContainer else { return }
        chatSession = ChatSession(container, instructions: buildSystemPrompt())
        currentResponse = ""

        if !messages.isEmpty {
            Task {
                for msg in messages.suffix(10) {
                    if msg.role == "user" {
                        let _ = try? await chatSession?.respond(to: msg.content)
                    }
                }
            }
        }
    }

    /// Generate a smart title for a conversation using LLM
    func generateTitle(userMessage: String, aiResponse: String) async -> String? {
        guard let container = modelContainer else { return nil }
        let titleSession = ChatSession(container, instructions: "Generate a very short title (3-5 words max) for a conversation. Reply ONLY with the title, nothing else.")
        let prompt = "User said: \(userMessage)\nAI replied: \(aiResponse)"
        let title = try? await titleSession.respond(to: prompt)
        return title?.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"\'")))
    }

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
