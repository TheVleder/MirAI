import Foundation
import Observation
import AVFoundation
import Speech

/// Manages the full audio pipeline: mic capture, on-device STT, TTS,
/// with barge-in, VAD, continuous listening, and voice selection.
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

    enum ListeningMode: String, CaseIterable {
        case pushToTalk = "Push to Talk"
        case handsFree = "Hands-Free"
    }

    var state: AudioState = .idle
    var recognizedText: String = ""
    var isAuthorized: Bool = false
    var listeningMode: ListeningMode = .pushToTalk {
        didSet { UserDefaults.standard.set(listeningMode.rawValue, forKey: "listeningMode") }
    }
    var audioLevel: Float = 0 // 0.0 to 1.0, for UI visualization

    /// Selected TTS voice identifier (persisted)
    var selectedVoiceID: String? {
        didSet { UserDefaults.standard.set(selectedVoiceID, forKey: "selectedVoiceID") }
    }

    /// Callback for when hands-free VAD detects end of speech
    var onHandsFreeUtteranceComplete: ((String) -> Void)?

    // MARK: - Private Properties

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var ttsDelegate: TTSDelegate?

    // VAD properties
    private var silenceTimer: Timer?
    private let vadSilenceThreshold: TimeInterval = 1.5 // seconds of silence before stopping
    private let vadPowerThreshold: Float = -40.0 // dB threshold for speech detection

    // MARK: - Initialization

    override init() {
        super.init()
        // Restore persisted preferences
        if let mode = UserDefaults.standard.string(forKey: "listeningMode") {
            listeningMode = ListeningMode(rawValue: mode) ?? .pushToTalk
        }
        selectedVoiceID = UserDefaults.standard.string(forKey: "selectedVoiceID")

        ttsDelegate = TTSDelegate { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                self.state = .idle
                // In hands-free mode, restart listening after speaking
                if self.listeningMode == .handsFree {
                    self.startListening()
                }
            }
        }
        synthesizer.delegate = ttsDelegate
    }

    // MARK: - Available Voices

    /// Get all available TTS voices for current language
    static func availableVoices(for language: String = "en") -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    /// Quality label for a voice
    static func qualityLabel(for voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Default"
        }
    }

    // MARK: - Permissions

    func requestPermissions() async {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

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

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Barge-In

    /// Interrupt TTS immediately and start listening (barge-in)
    func bargeIn() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        state = .idle
        startListening()
    }

    // MARK: - Speech-to-Text (STT)

    func startListening() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            recognizedText = "Speech recognition not available."
            return
        }

        // Stop any ongoing TTS (barge-in support)
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        do {
            try configureAudioSession()
        } catch {
            recognizedText = "Audio session error: \(error.localizedDescription)"
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        recognizedText = ""
        state = .listening

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)

            // Calculate audio power level for VAD and UI
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(max(frameLength, 1)))
            let avgPower = 20 * log10(max(rms, 0.000001))

            Task { @MainActor in
                guard let self = self else { return }
                // Normalize to 0-1 range (roughly -60dB to 0dB)
                self.audioLevel = max(0, min(1, (avgPower + 60) / 60))

                // VAD: reset silence timer when speech detected
                if self.listeningMode == .handsFree && avgPower > self.vadPowerThreshold {
                    self.resetSilenceTimer()
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            recognizedText = "Audio engine error: \(error.localizedDescription)"
            state = .idle
            return
        }

        // Start silence timer for hands-free mode
        if listeningMode == .handsFree {
            resetSilenceTimer()
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    self.recognizedText = result.bestTranscription.formattedString

                    // Reset silence timer on new speech in hands-free mode
                    if self.listeningMode == .handsFree {
                        self.resetSilenceTimer()
                    }
                }

                if error != nil || (result?.isFinal ?? false) {
                    if self.state == .listening {
                        self.state = .processing
                    }
                }
            }
        }
    }

    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioLevel = 0

        if state == .listening {
            state = .processing
        }
    }

    // MARK: - VAD Silence Timer

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: vadSilenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let text = self.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty && self.state == .listening {
                    self.stopListening()
                    self.onHandsFreeUtteranceComplete?(text)
                }
            }
        }
    }

    // MARK: - Text-to-Speech (TTS)

    func speak(_ text: String) {
        guard !text.isEmpty else {
            state = .idle
            return
        }

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

        // Use selected voice or default
        if let voiceID = selectedVoiceID,
           let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }

        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        state = .idle
    }

    // MARK: - Cleanup

    func cleanup() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        stopListening()
        stopSpeaking()
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}

// MARK: - TTS Delegate

private final class TTSDelegate: NSObject, AVSpeechSynthesizerDelegate, Sendable {
    let onFinish: @Sendable () -> Void

    init(onFinish: @escaping @Sendable () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }
}
