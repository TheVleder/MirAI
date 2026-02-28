import SwiftUI

/// Voice chat interface with push-to-talk, state indicators, message history, and model management.
struct ChatView: View {

    @Environment(ModelDownloader.self) private var downloader
    @Environment(LLMManager.self) private var llm
    @Environment(AudioManager.self) private var audio

    @State private var messages: [ChatMessage] = []
    @State private var isHolding = false
    @State private var modelLoaded = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.05, green: 0.05, blue: 0.12)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header

                // Messages
                messageList

                // State indicator
                stateIndicator

                // Talk button
                talkButton
                    .padding(.bottom, 40)
            }
        }
        .task {
            await audio.requestPermissions()
            if let modelID = downloader.downloadedModelID {
                await llm.loadModel(modelID: modelID)
                modelLoaded = true
            }
        }
        .alert("Delete Model", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                llm.unloadModel()
                messages.removeAll()
                modelLoaded = false
                downloader.deleteCurrentModel()
            }
        } message: {
            Text("This will delete the current model (\\(llm.loadedModelName)) and free storage. You'll be taken back to the download screen to choose a new model.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MirAI")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                HStack(spacing: 6) {
                    Circle()
                        .fill(modelLoaded ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(modelLoaded ? llm.loadedModelName : "Loading model…")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Delete model button
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash.circle")
                    .font(.title2)
                    .foregroundColor(.red.opacity(0.5))
            }

            // Reset conversation button
            Button {
                llm.resetConversation()
                messages.removeAll()
            } label: {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
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
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
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

            Image(systemName: "waveform.and.mic")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.15))

            Text("Hold the button to speak")
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
                    PulsingDot(color: .red)
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
                case .idle:
                    if llm.state == .generating {
                        PulsingDot(color: .purple)
                        Text("Thinking…")
                            .foregroundColor(.purple.opacity(0.9))
                    } else if llm.state == .loading {
                        ProgressView()
                            .tint(.white.opacity(0.5))
                            .scaleEffect(0.7)
                        Text("Loading model…")
                            .foregroundColor(.white.opacity(0.5))
                    } else {
                        Text("Ready")
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

    // MARK: - Talk Button

    private var talkButton: some View {
        ZStack {
            // Outer glow when holding
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

            // Main button
            Circle()
                .fill(
                    isHolding
                    ? LinearGradient(
                        colors: [.red.opacity(0.9), .orange.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    : LinearGradient(
                        colors: [.cyan.opacity(0.8), .blue.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 88, height: 88)
                .shadow(
                    color: isHolding ? .red.opacity(0.4) : .cyan.opacity(0.3),
                    radius: 20,
                    y: 8
                )
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
                        startTalking()
                    }
                }
                .onEnded { _ in
                    stopTalking()
                }
        )
        .disabled(!modelLoaded || !audio.isAuthorized || llm.state == .generating || audio.state == .speaking)
        .opacity(modelLoaded && audio.isAuthorized ? 1 : 0.4)
    }

    // MARK: - Actions

    private func startTalking() {
        isHolding = true
        audio.stopSpeaking()
        audio.startListening()

        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }

    private func stopTalking() {
        isHolding = false
        audio.stopListening()

        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        let userText = audio.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: userText))

        Task {
            let response = await llm.generate(prompt: userText)
            messages.append(ChatMessage(role: .assistant, content: response))
            audio.speak(response)
        }
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp = Date()

    enum Role {
        case user
        case assistant
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        message.role == .user
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.5),
                                    Color.cyan.opacity(0.3)
                                ],
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

            if message.role == .assistant { Spacer(minLength: 60) }
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
