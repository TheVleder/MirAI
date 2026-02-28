import Foundation
import Observation
import AVFoundation
import Speech

/// Manages the full audio pipeline: microphone capture, on-device STT, and native TTS.
@Observable
@MainActor
final class AudioManager: NSObject {

    // MARK: - State

    enum AudioState: Equatable {
        case idle
        case listening
        case processing
        case speaking
    }

    var state: AudioState = .idle
    var recognizedText: String = ""
    var isAuthorized: Bool = false

    // MARK: - Private Properties

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var ttsDelegate: TTSDelegate?

    // MARK: - Initialization

    override init() {
        super.init()
        ttsDelegate = TTSDelegate { [weak self] in
            Task { @MainActor in
                self?.state = .idle
            }
        }
        synthesizer.delegate = ttsDelegate
    }

    // MARK: - Permissions

    /// Request microphone and speech recognition permissions
    func requestPermissions() async {
        // Request speech recognition authorization
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        // Request microphone access
        let micGranted: Bool
        if #available(iOS 17.0, *) {
            micGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micGranted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        isAuthorized = (speechStatus == .authorized) && micGranted
    }

    // MARK: - Audio Session

    /// Configure the shared audio session for voice chat
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Speech-to-Text (STT)

    /// Start listening via the microphone with on-device speech recognition
    func startListening() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            recognizedText = "Speech recognition not available."
            return
        }

        do {
            try configureAudioSession()
        } catch {
            recognizedText = "Audio session error: \(error.localizedDescription)"
            return
        }

        // Cancel any running task
        recognitionTask?.cancel()
        recognitionTask = nil

        recognizedText = ""
        state = .listening

        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        recognitionRequest = request

        // Setup audio engine input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            recognizedText = "Audio engine error: \(error.localizedDescription)"
            state = .idle
            return
        }

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    self.recognizedText = result.bestTranscription.formattedString
                }

                if error != nil || (result?.isFinal ?? false) {
                    // Recognition ended
                    if self.state == .listening {
                        self.state = .processing
                    }
                }
            }
        }
    }

    /// Stop listening and finalize the recognized text
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if state == .listening {
            state = .processing
        }
    }

    // MARK: - Text-to-Speech (TTS)

    /// Speak the given text using on-device TTS
    func speak(_ text: String) {
        guard !text.isEmpty else {
            state = .idle
            return
        }

        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        do {
            try configureAudioSession()
        } catch {
            state = .idle
            return
        }

        state = .speaking

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Use a high-quality voice if available
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }

        synthesizer.speak(utterance)
    }

    /// Stop any current speech output
    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        state = .idle
    }

    // MARK: - Cleanup

    func cleanup() {
        stopListening()
        stopSpeaking()
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}

// MARK: - TTS Delegate

/// Delegate to track when speech synthesis finishes
private class TTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }
}
