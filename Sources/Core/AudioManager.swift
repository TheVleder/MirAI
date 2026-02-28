import Foundation
import Observation
import AVFoundation
import Speech

/// Full audio pipeline: STT, TTS with sentence queuing, barge-in with mic monitoring,
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

    /// TTS speech rate multiplier (0.8 to 1.5)
    var speechRate: Float = 1.0 {
        didSet { UserDefaults.standard.set(speechRate, forKey: "speechRate") }
    }

    /// Callback when hands-free VAD detects end of speech
    var onHandsFreeUtteranceComplete: ((String) -> Void)?

    /// Callback when auto barge-in fires (user speaks during TTS)
    var onAutoBargeIn: (() -> Void)?

    // MARK: - Private

    private var speechRecognizer: SFSpeechRecognizer?
    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var ttsDelegate: TTSDelegate?

    // Tap / engine state
    private var hasTapInstalled = false

    // VAD
    private var silenceTimer: Timer?
    private let vadSilenceThreshold: TimeInterval = 1.8
    private let vadSpeechThreshold: Float = -35.0

    // Barge-in monitoring
    private var isMonitoringForBargeIn = false
    private var bargeInSpeechFrames: Int = 0
    private let bargeInFramesNeeded: Int = 4 // ~0.2s sustained speech
    private let bargeInThreshold: Float = -42.0 // More sensitive than VAD

    // Sentence queue for streaming TTS
    private var sentenceQueue: [String] = []
    private var isSpeakingFromQueue = false

    // MARK: - Init

    override init() {
        super.init()
        if let mode = UserDefaults.standard.string(forKey: "listeningMode") {
            listeningMode = ListeningMode(rawValue: mode) ?? .pushToTalk
        }
        selectedVoiceID = UserDefaults.standard.string(forKey: "selectedVoiceID")
        speechRate = UserDefaults.standard.object(forKey: "speechRate") as? Float ?? 1.0

        let lang = AppLanguage.saved()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: lang.sttLocale))
        if selectedVoiceID == nil {
            selectedVoiceID = Self.bestAvailableVoice(for: lang.ttsLanguage)?.identifier
        }

        ttsDelegate = TTSDelegate { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                // Check if more sentences in queue
                if !self.sentenceQueue.isEmpty {
                    self.speakNextSentence()
                } else {
                    self.isSpeakingFromQueue = false
                    self.stopMonitorTap()
                    self.state = .idle
                    if self.listeningMode == .handsFree {
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        if self.state == .idle {
                            self.startListening()
                        }
                    }
                }
            }
        }
        synthesizer.delegate = ttsDelegate
    }

    // MARK: - Language

    func setLanguage(_ language: AppLanguage) {
        language.save()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language.sttLocale))
        selectedVoiceID = Self.bestAvailableVoice(for: language.ttsLanguage)?.identifier
    }

    // MARK: - Voice Helpers

    static func availableVoices(for languagePrefix: String? = nil) -> [AVSpeechSynthesisVoice] {
        var voices = AVSpeechSynthesisVoice.speechVoices()
        if let prefix = languagePrefix, !prefix.isEmpty {
            voices = voices.filter { $0.language.hasPrefix(prefix) }
        }
        return voices.sorted { $0.quality.rawValue > $1.quality.rawValue }
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

    /// Configure for STT (voice chat mode with echo cancellation)
    private func configureForSTT() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .mixWithOthers, .duckOthers]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Configure for TTS + barge-in monitoring (default mode — NO echo cancellation)
    private func configureForTTSMonitor() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .mixWithOthers, .duckOthers, .allowBluetooth]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Tap Management

    private func removeTapIfNeeded() {
        if hasTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasTapInstalled = false
        }
    }

    private func safeStopEngine() {
        removeTapIfNeeded()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        isMonitoringForBargeIn = false
    }

    // MARK: - Barge-In

    /// Manual barge-in (button tap)
    func bargeIn() {
        guard state == .speaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        sentenceQueue.removeAll()
        isSpeakingFromQueue = false
        stopMonitorTap()
        state = .idle
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            if self.state == .idle {
                self.startListening()
            }
        }
    }

    /// Start a lightweight mic tap to detect voice during TTS.
    /// Uses .default mode (not .voiceChat) so echo cancellation doesn't suppress the mic.
    private func startMonitorTap() {
        guard listeningMode == .handsFree else { return }
        stopMonitorTap()

        do {
            try configureForTTSMonitor()
        } catch { return }

        bargeInSpeechFrames = 0
        isMonitoringForBargeIn = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            var sum: Float = 0
            for i in 0..<frameLength { sum += channelData[i] * channelData[i] }
            let rms = sqrt(sum / Float(frameLength))
            let power = 20 * log10(max(rms, 0.000001))

            Task { @MainActor in
                guard let self = self, self.state == .speaking, self.isMonitoringForBargeIn else { return }

                // Use more sensitive threshold for barge-in
                if power > self.bargeInThreshold {
                    self.bargeInSpeechFrames += 1
                } else {
                    self.bargeInSpeechFrames = max(0, self.bargeInSpeechFrames - 1)
                }

                if self.bargeInSpeechFrames >= self.bargeInFramesNeeded {
                    self.bargeInSpeechFrames = 0
                    self.isMonitoringForBargeIn = false
                    self.synthesizer.stopSpeaking(at: .immediate)
                    self.sentenceQueue.removeAll()
                    self.isSpeakingFromQueue = false
                    self.removeTapIfNeeded()
                    if self.audioEngine.isRunning { self.audioEngine.stop() }
                    self.state = .idle
                    self.onAutoBargeIn?()
                }
            }
        }
        hasTapInstalled = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            stopMonitorTap()
        }
    }

    private func stopMonitorTap() {
        isMonitoringForBargeIn = false
        bargeInSpeechFrames = 0
        removeTapIfNeeded()
        if audioEngine.isRunning { audioEngine.stop() }
    }

    // MARK: - STT

    func startListening() {
        guard state == .idle || state == .processing else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            recognizedText = "Speech recognition not available."
            return
        }

        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        stopMonitorTap()

        recognitionTask?.cancel()
        recognitionTask = nil
        safeStopEngine()

        do { try configureForSTT() } catch {
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
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            state = .idle
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let len = Int(buffer.frameLength)
            guard len > 0 else { return }
            var sum: Float = 0
            for i in 0..<len { sum += channelData[i] * channelData[i] }
            let rms = sqrt(sum / Float(len))
            let power = 20 * log10(max(rms, 0.000001))
            Task { @MainActor in
                guard let self = self else { return }
                self.audioLevel = max(0, min(1, (power + 60) / 60))
                if self.listeningMode == .handsFree && power > self.vadSpeechThreshold {
                    self.resetSilenceTimer()
                }
            }
        }
        hasTapInstalled = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            state = .idle
            safeStopEngine()
            return
        }

        if listeningMode == .handsFree { resetSilenceTimer() }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self, self.state == .listening else { return }
                if let result = result {
                    self.recognizedText = result.bestTranscription.formattedString
                    if self.listeningMode == .handsFree { self.resetSilenceTimer() }
                }
                if result?.isFinal == true || error != nil {
                    if self.state == .listening { self.state = .processing }
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
        if state == .listening { state = .processing }
    }

    // MARK: - VAD Silence Timer

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: vadSilenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.state == .listening else { return }
                let text = self.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                self.stopListening()
                self.onHandsFreeUtteranceComplete?(text)
            }
        }
    }

    // MARK: - TTS

    /// Speak the full text at once
    func speak(_ text: String) {
        guard !text.isEmpty else { state = .idle; return }

        // Stop STT fully
        silenceTimer?.invalidate()
        silenceTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        safeStopEngine()

        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        sentenceQueue.removeAll()
        isSpeakingFromQueue = false

        state = .speaking
        speakUtterance(text)

        // Start mic monitoring for auto barge-in
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if self.state == .speaking {
                self.startMonitorTap()
            }
        }
    }

    /// Queue a sentence for streaming TTS (speaks immediately if nothing playing)
    func queueSentence(_ sentence: String) {
        guard !sentence.isEmpty else { return }

        if state != .speaking {
            // First sentence — stop STT fully
            silenceTimer?.invalidate()
            silenceTimer = nil
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest?.endAudio()
            recognitionRequest = nil
            safeStopEngine()

            if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
            sentenceQueue.removeAll()

            state = .speaking
            isSpeakingFromQueue = true
            speakUtterance(sentence)

            // Start mic monitoring for barge-in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                if self.state == .speaking {
                    self.startMonitorTap()
                }
            }
        } else {
            // Already speaking — queue for later
            sentenceQueue.append(sentence)
        }
    }

    /// Speak the next queued sentence
    private func speakNextSentence() {
        guard !sentenceQueue.isEmpty else { return }
        let next = sentenceQueue.removeFirst()
        speakUtterance(next)
    }

    /// Internal: create and speak an utterance
    private func speakUtterance(_ text: String) {
        do { try configureForTTSMonitor() } catch { return }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * speechRate
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.02
        utterance.postUtteranceDelay = 0.05

        if let voiceID = selectedVoiceID,
           let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else if let best = Self.bestAvailableVoice() {
            utterance.voice = best
        }

        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        sentenceQueue.removeAll()
        isSpeakingFromQueue = false
        stopMonitorTap()
        state = .idle
    }

    // MARK: - Cleanup

    func cleanup() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        stopMonitorTap()
        safeStopEngine()
        sentenceQueue.removeAll()
        isSpeakingFromQueue = false
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}

// MARK: - TTS Delegate

private final class TTSDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    let onFinish: @Sendable () -> Void
    init(onFinish: @escaping @Sendable () -> Void) { self.onFinish = onFinish }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { onFinish() }
}
