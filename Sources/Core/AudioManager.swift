import Foundation
import Observation
import AVFoundation
import Speech

/// Full audio pipeline: STT, TTS, barge-in with mic monitoring during playback,
/// VAD for hands-free mode, and voice selection.
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
    var audioLevel: Float = 0

    /// Selected TTS voice identifier (persisted)
    var selectedVoiceID: String? {
        didSet { UserDefaults.standard.set(selectedVoiceID, forKey: "selectedVoiceID") }
    }

    /// Callback when hands-free VAD detects end of speech
    var onHandsFreeUtteranceComplete: ((String) -> Void)?

    /// Callback when auto barge-in fires (user speaks during TTS)
    var onAutoBargeIn: (() -> Void)?

    // MARK: - Private

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var ttsDelegate: TTSDelegate?

    // Tap / engine state
    private var hasTapInstalled = false
    private var isEngineRunning = false

    // VAD
    private var silenceTimer: Timer?
    private let vadSilenceThreshold: TimeInterval = 1.8
    private let vadSpeechThreshold: Float = -35.0

    // Barge-in monitoring during TTS
    private var bargeInEngine: AVAudioEngine?
    private var bargeInTapInstalled = false
    private var bargeInSpeechFrames: Int = 0
    private let bargeInFramesNeeded: Int = 8 // ~0.4s of sustained speech

    // MARK: - Init

    override init() {
        super.init()
        if let mode = UserDefaults.standard.string(forKey: "listeningMode") {
            listeningMode = ListeningMode(rawValue: mode) ?? .pushToTalk
        }
        selectedVoiceID = UserDefaults.standard.string(forKey: "selectedVoiceID")
        if selectedVoiceID == nil {
            selectedVoiceID = Self.bestAvailableVoice()?.identifier
        }

        ttsDelegate = TTSDelegate { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                self.stopBargeInMonitor()
                self.state = .idle
                // Auto-restart listening in hands-free
                if self.listeningMode == .handsFree {
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s gap
                    if self.state == .idle {
                        self.startListening()
                    }
                }
            }
        }
        synthesizer.delegate = ttsDelegate
    }

    // MARK: - Voice Helpers

    static func availableVoices(for language: String = "en") -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    static func qualityLabel(for voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Default"
        }
    }

    static func bestAvailableVoice(for language: String = "en-US") -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
            .first
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
            options: [.defaultToSpeaker, .mixWithOthers]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Engine & Tap Safety

    private func safeStopEngine() {
        if hasTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasTapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        isEngineRunning = false
    }

    // MARK: - Barge-In

    /// Manual barge-in: stop TTS, clean up, start listening
    func bargeIn() {
        guard state == .speaking else { return }

        synthesizer.stopSpeaking(at: .immediate)
        stopBargeInMonitor()
        state = .idle

        // Small delay to let audio session settle
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            if self.state == .idle {
                self.startListening()
            }
        }
    }

    // MARK: - Barge-In Monitor (mic during TTS)

    /// Start a separate AVAudioEngine to monitor mic input during TTS
    private func startBargeInMonitor() {
        guard listeningMode == .handsFree else { return }
        stopBargeInMonitor()

        bargeInSpeechFrames = 0
        let monitor = AVAudioEngine()
        bargeInEngine = monitor

        let inputNode = monitor.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0 && format.channelCount > 0 else { return }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(frameLength))
            let power = 20 * log10(max(rms, 0.000001))

            Task { @MainActor in
                guard let self = self, self.state == .speaking else { return }

                if power > self.vadSpeechThreshold {
                    self.bargeInSpeechFrames += 1
                } else {
                    self.bargeInSpeechFrames = max(0, self.bargeInSpeechFrames - 1)
                }

                // Sustained speech detected → auto barge-in
                if self.bargeInSpeechFrames >= self.bargeInFramesNeeded {
                    self.bargeInSpeechFrames = 0
                    self.synthesizer.stopSpeaking(at: .immediate)
                    self.stopBargeInMonitor()
                    self.state = .idle
                    self.onAutoBargeIn?()
                }
            }
        }
        bargeInTapInstalled = true

        do {
            monitor.prepare()
            try monitor.start()
        } catch {
            stopBargeInMonitor()
        }
    }

    private func stopBargeInMonitor() {
        if bargeInTapInstalled, let engine = bargeInEngine {
            engine.inputNode.removeTap(onBus: 0)
            bargeInTapInstalled = false
        }
        bargeInEngine?.stop()
        bargeInEngine = nil
        bargeInSpeechFrames = 0
    }

    // MARK: - STT

    func startListening() {
        guard state == .idle || state == .processing else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            recognizedText = "Speech recognition not available."
            return
        }

        // Stop TTS if somehow still running
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        stopBargeInMonitor()

        // Full cleanup of main engine
        recognitionTask?.cancel()
        recognitionTask = nil
        safeStopEngine()

        do {
            try configureAudioSession()
        } catch {
            recognizedText = "Audio session error."
            return
        }

        recognizedText = ""
        state = .listening

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            state = .idle
            recognizedText = "Mic format error."
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(frameLength))
            let avgPower = 20 * log10(max(rms, 0.000001))

            Task { @MainActor in
                guard let self = self else { return }
                self.audioLevel = max(0, min(1, (avgPower + 60) / 60))

                if self.listeningMode == .handsFree && avgPower > self.vadSpeechThreshold {
                    self.resetSilenceTimer()
                }
            }
        }
        hasTapInstalled = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isEngineRunning = true
        } catch {
            recognizedText = "Audio engine start error."
            state = .idle
            safeStopEngine()
            return
        }

        if listeningMode == .handsFree {
            resetSilenceTimer()
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.state == .listening else { return } // Ignore stale callbacks

                if let result = result {
                    self.recognizedText = result.bestTranscription.formattedString
                    if self.listeningMode == .handsFree {
                        self.resetSilenceTimer()
                    }
                }

                if result?.isFinal == true || error != nil {
                    // Only transition to processing if we're still listening
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
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        safeStopEngine()
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
                guard self.state == .listening else { return }
                let text = self.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                self.stopListening()
                self.onHandsFreeUtteranceComplete?(text)
            }
        }
    }

    // MARK: - TTS

    func speak(_ text: String) {
        guard !text.isEmpty else {
            state = .idle
            return
        }

        // Clean up STT engine before TTS
        silenceTimer?.invalidate()
        silenceTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        safeStopEngine()

        do {
            try configureAudioSession()
        } catch {
            state = .idle
            return
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        state = .speaking

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.1

        if let voiceID = selectedVoiceID,
           let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else if let best = Self.bestAvailableVoice() {
            utterance.voice = best
        }

        synthesizer.speak(utterance)

        // Start monitoring mic for auto barge-in (hands-free)
        // Small delay so TTS audio output stabilizes (avoids false trigger)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            if self.state == .speaking {
                self.startBargeInMonitor()
            }
        }
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        stopBargeInMonitor()
        state = .idle
    }

    // MARK: - Cleanup

    func cleanup() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        stopBargeInMonitor()
        safeStopEngine()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}

// MARK: - TTS Delegate

private final class TTSDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    let onFinish: @Sendable () -> Void

    init(onFinish: @escaping @Sendable () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }
}
