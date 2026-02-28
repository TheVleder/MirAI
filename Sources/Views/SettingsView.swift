import SwiftUI
import AVFoundation
import SwiftData

/// Settings screen: personality picker, voice selector, listening mode, model info.
struct SettingsView: View {

    @Environment(LLMManager.self) private var llm
    @Environment(AudioManager.self) private var audio
    @Environment(ModelDownloader.self) private var downloader
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var availableVoices: [AVSpeechSynthesisVoice] = []
    @State private var customPersonas: [CustomPersonality] = []
    @State private var showPersonaEditor = false
    @State private var editingPersona: CustomPersonality?
    @State private var modelSizeString: String = "Calculating…"
    @State private var showDeleteModelConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.12)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        personalitySection
                        voiceSection
                        speechSpeedSection
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
                availableVoices = AudioManager.availableVoices(for: llm.activeLanguage.rawValue)
                loadCustomPersonas()
                calculateModelSize()
            }
            .onChange(of: llm.activeLanguage) { _, newLang in
                availableVoices = AudioManager.availableVoices(for: newLang.rawValue)
            }
            .sheet(isPresented: $showPersonaEditor) {
                CustomPersonaEditorView(existingPersona: editingPersona) {
                    loadCustomPersonas()
                }
            }
            .alert("Delete Model?", isPresented: $showDeleteModelConfirm) {
                Button("Delete", role: .destructive) { deleteModel() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will free \(modelSizeString) of storage. You can re-download anytime.")
            }
        }
    }

    // MARK: - Custom Persona Helpers

    private func loadCustomPersonas() {
        let descriptor = FetchDescriptor<CustomPersonality>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        customPersonas = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Personality Section

    private var personalitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Personality", icon: "theatermasks")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                // Built-in
                ForEach(Personality.all) { personality in
                    personalityCard(personality)
                }

                // Custom
                ForEach(customPersonas) { custom in
                    customPersonalityCard(custom)
                }

                // Create new
                createPersonalityCard
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
                    .fill(isSelected ? Color.cyan.opacity(0.15) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.cyan.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
        }
    }

    private func customPersonalityCard(_ custom: CustomPersonality) -> some View {
        let persona = custom.toPersonality()
        let isSelected = llm.activePersonality.id == persona.id

        return Button {
            withAnimation(.spring(response: 0.3)) {
                llm.switchPersonality(persona)
            }
        } label: {
            VStack(spacing: 6) {
                Text(custom.emoji)
                    .font(.system(size: 28))

                Text(custom.name)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("Custom")
                    .font(.system(size: 9))
                    .foregroundColor(.purple.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.purple.opacity(0.15) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.purple.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
        }
        .contextMenu {
            Button {
                editingPersona = custom
                showPersonaEditor = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                modelContext.delete(custom)
                try? modelContext.save()
                loadCustomPersonas()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var createPersonalityCard: some View {
        Button {
            editingPersona = nil
            showPersonaEditor = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.cyan.opacity(0.6))

                Text("Create")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                    .foregroundColor(.white.opacity(0.15))
            )
        }
    }

    // MARK: - Voice Section

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Voice", icon: "speaker.wave.3")

            if availableVoices.isEmpty {
                Text("No voices available for \(llm.activeLanguage.name)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(availableVoices.prefix(15), id: \.identifier) { voice in
                            voiceCard(voice)
                        }
                    }
                    .padding(.horizontal, 2)
                }

                Text("Tip: Download better voices in iPhone Settings → Accessibility → Spoken Content → Voices → \(llm.activeLanguage.name)")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.horizontal, 4)
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

    // MARK: - Speech Speed Section

    private var speechSpeedSection: some View {
        @Bindable var audio = audio

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Speech Speed", icon: "gauge.open.with.lines.needle.33percent.and.arrowtriangle")

            VStack(spacing: 8) {
                HStack {
                    Text("🐢")
                    Slider(value: $audio.speechRate, in: 0.8...1.5, step: 0.05)
                        .tint(.cyan)
                    Text("🐇")
                }

                Text(String(format: "%.0f%%", audio.speechRate * 100))
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundColor(.cyan)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
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
        @Bindable var downloader = downloader

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Model", icon: "cpu")

            VStack(spacing: 10) {
                infoRow("Loaded", value: llm.loadedModelName.isEmpty ? "None" : llm.loadedModelName)
                infoRow("Status", value: stateLabel)
                infoRow("Storage", value: modelSizeString)

                // Model ID input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model ID")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))

                    TextField("mlx-community/model-name", text: $downloader.modelID)
                        .textFieldStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.top, 4)

                // Download / Switch model
                Button {
                    Task {
                        await downloader.downloadModel()
                        if downloader.isModelReady, let id = downloader.downloadedModelID {
                            await llm.loadModel(modelID: id)
                        }
                        calculateModelSize()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(downloader.downloadedModelID != nil ? "Switch Model" : "Download Model")
                    }
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [.cyan.opacity(0.7), .blue.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Delete
                if downloader.downloadedModelID != nil {
                    Button {
                        showDeleteModelConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Model")
                        }
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
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

    // MARK: - Model Size Calculation

    private func calculateModelSize() {
        Task {
            let size = await getModelDirectorySize()
            modelSizeString = size
        }
    }

    private func getModelDirectorySize() async -> String {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let hubDir = cacheDir?.appendingPathComponent("huggingface/hub") else {
            return "No model"
        }

        guard FileManager.default.fileExists(atPath: hubDir.path) else {
            return "No model"
        }

        var totalSize: UInt64 = 0
        if let enumerator = FileManager.default.enumerator(at: hubDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += UInt64(size)
                }
            }
        }

        if totalSize == 0 { return "No model" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(totalSize))
    }

    private func deleteModel() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        if let hubDir = cacheDir?.appendingPathComponent("huggingface/hub") {
            try? FileManager.default.removeItem(at: hubDir)
        }
        downloader.downloadedModelID = nil
        modelSizeString = "No model"
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
