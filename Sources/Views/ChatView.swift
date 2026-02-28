import SwiftUI

/// Voice chat interface with barge-in, hands-free mode, SwiftData persistence, and personality display.
struct ChatView: View {

    @Environment(ModelDownloader.self) private var downloader
    @Environment(LLMManager.self) private var llm
    @Environment(AudioManager.self) private var audio
    @Environment(ConversationManager.self) private var conversationManager

    @State private var isHolding = false
    @State private var modelLoaded = false

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.05, green: 0.05, blue: 0.12)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                messageList
                stateIndicator
                controlArea
                    .padding(.bottom, 30)
            }
        }
        .navigationBarBackButtonHidden(false)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await audio.requestPermissions()
            if let modelID = downloader.downloadedModelID, llm.state != .ready {
                await llm.loadModel(modelID: modelID)
                modelLoaded = true
            } else if llm.state == .ready {
                modelLoaded = true
            }

            // Set up hands-free callback
            audio.onHandsFreeUtteranceComplete = { text in
                Task { @MainActor in
                    handleUserUtterance(text)
                }
            }

            // Set up auto barge-in (user speaks while AI is talking)
            audio.onAutoBargeIn = {
                Task { @MainActor in
                    audio.startListening()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(llm.activePersonality.emoji)
                        .font(.title3)
                    Text("MirAI")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(modelLoaded ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(modelLoaded ? "\(llm.loadedModelName) · \(llm.activePersonality.name)" : "Loading model…")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Language picker
            Menu {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        llm.activeLanguage = lang
                        audio.setLanguage(lang)
                    } label: {
                        HStack {
                            Text("\(lang.flag) \(lang.name)")
                            if llm.activeLanguage == lang {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(llm.activeLanguage.flag)
                    .font(.title2)
            }

            // Reset conversation
            Button {
                llm.resetConversation()
            } label: {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    let messages = conversationManager.currentMessages
                    if messages.isEmpty {
                        emptyState
                    }

                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: conversationManager.currentMessages.count) { _, _ in
                if let last = conversationManager.currentMessages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)

            Text(llm.activePersonality.emoji)
                .font(.system(size: 48))

            Text(audio.listeningMode == .pushToTalk
                 ? "Hold the button to speak"
                 : "Tap the mic to start listening")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.3))

            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - State Indicator

    private var stateIndicator: some View {
        HStack(spacing: 10) {
            Group {
                switch audio.state {
                case .listening:
                    audioLevelBar
                    Text("Listening…")
                        .foregroundColor(.red.opacity(0.9))
                case .processing:
                    PulsingDot(color: .orange)
                    Text("Processing…")
                        .foregroundColor(.orange.opacity(0.9))
                case .speaking:
                    PulsingDot(color: .cyan)
                    Text("Speaking…")
                        .foregroundColor(.cyan.opacity(0.9))

                    // Barge-in hint
                    Button {
                        audio.bargeIn()
                    } label: {
                        Text("Interrupt")
                            .font(.system(.caption2, weight: .semibold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.15))
                            .clipShape(Capsule())
                    }
                case .idle:
                    if llm.state == .generating {
                        PulsingDot(color: .purple)
                        Text("Thinking…")
                            .foregroundColor(.purple.opacity(0.9))
                    } else if llm.state == .loading {
                        ProgressView()
                            .tint(.white.opacity(0.5))
                            .scaleEffect(0.7)
                        Text("Loading…")
                            .foregroundColor(.white.opacity(0.5))
                    } else {
                        Text(audio.listeningMode == .handsFree ? "🎙 Hands-Free" : "Ready")
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }
            .font(.system(.subheadline, design: .rounded, weight: .medium))
        }
        .frame(height: 32)
        .animation(.easeInOut(duration: 0.3), value: audio.state)
        .animation(.easeInOut(duration: 0.3), value: llm.state)
        .padding(.vertical, 8)
    }

    /// Audio level visualization bar
    private var audioLevelBar: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red.opacity(Double(i) * 0.2 < Double(audio.audioLevel) ? 0.9 : 0.2))
                    .frame(width: 3, height: CGFloat(4 + i * 3))
            }
        }
        .animation(.easeOut(duration: 0.1), value: audio.audioLevel)
    }

    // MARK: - Control Area

    private var controlArea: some View {
        Group {
            if audio.listeningMode == .pushToTalk {
                pushToTalkButton
            } else {
                handsFreeButton
            }
        }
    }

    private var pushToTalkButton: some View {
        ZStack {
            if isHolding {
                Circle()
                    .fill(Color.cyan.opacity(0.1))
                    .frame(width: 140, height: 140)
                    .scaleEffect(isHolding ? 1.3 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: isHolding
                    )
            }

            Circle()
                .fill(
                    isHolding
                    ? LinearGradient(colors: [.red.opacity(0.9), .orange.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [.cyan.opacity(0.8), .blue.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 88, height: 88)
                .shadow(color: isHolding ? .red.opacity(0.4) : .cyan.opacity(0.3), radius: 20, y: 8)
                .overlay(
                    Image(systemName: isHolding ? "waveform" : "mic.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.white)
                        .symbolEffect(.variableColor, isActive: isHolding)
                )
                .scaleEffect(isHolding ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHolding)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isHolding {
                        // If AI is speaking, barge-in directly
                        if audio.state == .speaking {
                            audio.bargeIn()
                            isHolding = true
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        } else {
                            startPTT()
                        }
                    }
                }
                .onEnded { _ in
                    stopPTT()
                }
        )
        .disabled(!modelLoaded || !audio.isAuthorized || llm.state == .generating)
        .opacity(modelLoaded && audio.isAuthorized ? 1 : 0.4)
    }

    private var handsFreeButton: some View {
        let isActive = audio.state == .listening
        let isSpeaking = audio.state == .speaking

        return Button {
            if isSpeaking {
                // Barge-in: interrupt AI and start listening
                audio.bargeIn()
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            } else if isActive {
                audio.stopListening()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } else {
                audio.startListening()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } label: {
            Circle()
                .fill(
                    isSpeaking
                    ? LinearGradient(colors: [.orange.opacity(0.9), .red.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    : isActive
                    ? LinearGradient(colors: [.red.opacity(0.9), .orange.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [.green.opacity(0.8), .cyan.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 88, height: 88)
                .shadow(color: isActive ? .red.opacity(0.4) : isSpeaking ? .orange.opacity(0.4) : .green.opacity(0.3), radius: 20, y: 8)
                .overlay(
                    Image(systemName: isSpeaking ? "hand.raised.fill" : isActive ? "stop.fill" : "ear.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(.white)
                )
                .scaleEffect(isActive || isSpeaking ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSpeaking)
        }
        .disabled(!modelLoaded || !audio.isAuthorized || llm.state == .generating)
        .opacity(modelLoaded && audio.isAuthorized ? 1 : 0.4)
    }

    // MARK: - Actions

    private func startPTT() {
        isHolding = true
        audio.stopSpeaking()
        audio.startListening()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func stopPTT() {
        isHolding = false
        audio.stopListening()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let userText = audio.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }

        handleUserUtterance(userText)
    }

    private func handleUserUtterance(_ text: String) {
        conversationManager.addMessage(role: "user", content: text)

        Task {
            let response = await llm.generate(prompt: text)
            conversationManager.addMessage(role: "assistant", content: response)
            audio.speak(response)
        }
    }
}

// MARK: - Message Bubble (uses SwiftData Message)

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 60) }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        message.role == "user"
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.5), Color.cyan.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        : AnyShapeStyle(Color.white.opacity(0.08))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.horizontal, 8)
            }

            if message.role == "assistant" { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Pulsing Dot

struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.4 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
