import SwiftUI
import AVFoundation

/// Settings screen: personality picker, voice selector, listening mode, model info.
struct SettingsView: View {

    @Environment(LLMManager.self) private var llm
    @Environment(AudioManager.self) private var audio
    @Environment(ModelDownloader.self) private var downloader
    @Environment(\.dismiss) private var dismiss

    @State private var availableVoices: [AVSpeechSynthesisVoice] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.12)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        personalitySection
                        voiceSection
                        listeningModeSection
                        modelSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cyan)
                }
            }
            .onAppear {
                availableVoices = AudioManager.availableVoices()
            }
        }
    }

    // MARK: - Personality Section

    private var personalitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Personality", icon: "theatermasks")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(Personality.all) { personality in
                    personalityCard(personality)
                }
            }
        }
    }

    private func personalityCard(_ personality: Personality) -> some View {
        let isSelected = llm.activePersonality.id == personality.id

        return Button {
            withAnimation(.spring(response: 0.3)) {
                llm.switchPersonality(personality)
            }
        } label: {
            VStack(spacing: 6) {
                Text(personality.emoji)
                    .font(.system(size: 28))

                Text(personality.name)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(personality.description)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected
                          ? Color.cyan.opacity(0.15)
                          : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.cyan.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
        }
    }

    // MARK: - Voice Section

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Voice", icon: "speaker.wave.3")

            if availableVoices.isEmpty {
                Text("No voices available")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(availableVoices.prefix(12), id: \.identifier) { voice in
                            voiceCard(voice)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private func voiceCard(_ voice: AVSpeechSynthesisVoice) -> some View {
        let isSelected = audio.selectedVoiceID == voice.identifier
        let quality = AudioManager.qualityLabel(for: voice)

        return Button {
            withAnimation(.spring(response: 0.3)) {
                audio.selectedVoiceID = voice.identifier
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: qualityIcon(quality))
                    .font(.title2)
                    .foregroundColor(qualityColor(quality))

                Text(voice.name)
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(quality)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(qualityColor(quality))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(qualityColor(quality).opacity(0.15))
                    .clipShape(Capsule())
            }
            .frame(width: 90)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.cyan.opacity(0.12) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.cyan.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
        }
    }

    // MARK: - Listening Mode Section

    private var listeningModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Listening Mode", icon: "ear")

            HStack(spacing: 12) {
                ForEach(AudioManager.ListeningMode.allCases, id: \.rawValue) { mode in
                    let isSelected = audio.listeningMode == mode

                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            audio.listeningMode = mode
                        }
                    } label: {
                        HStack {
                            Image(systemName: mode == .pushToTalk ? "hand.tap" : "waveform.badge.mic")
                                .foregroundColor(isSelected ? .cyan : .white.opacity(0.5))
                            Text(mode.rawValue)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? Color.cyan.opacity(0.12) : Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.cyan.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                    }
                }
            }

            if audio.listeningMode == .handsFree {
                Text("MirAI will listen continuously and detect when you stop speaking using Voice Activity Detection.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Model", icon: "cpu")

            VStack(spacing: 8) {
                infoRow("Loaded", value: llm.loadedModelName.isEmpty ? "None" : llm.loadedModelName)
                infoRow("Status", value: stateLabel)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }

    private var stateLabel: String {
        switch llm.state {
        case .idle: return "Idle"
        case .loading: return "Loading…"
        case .ready: return "Ready"
        case .generating: return "Generating…"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.cyan)
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }

    private func qualityIcon(_ quality: String) -> String {
        switch quality {
        case "Premium": return "star.fill"
        case "Enhanced": return "star.leadinghalf.filled"
        default: return "star"
        }
    }

    private func qualityColor(_ quality: String) -> Color {
        switch quality {
        case "Premium": return .yellow
        case "Enhanced": return .green
        default: return .white.opacity(0.5)
        }
    }
}
