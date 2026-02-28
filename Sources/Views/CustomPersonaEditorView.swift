import SwiftUI
import SwiftData

/// Editor form for creating/editing custom AI personalities.
struct CustomPersonaEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var existingPersona: CustomPersonality?
    var onSave: (() -> Void)?

    @State private var name: String = ""
    @State private var emoji: String = "🤖"
    @State private var description: String = ""
    @State private var systemPrompt: String = ""

    private let emojiOptions = ["🤖", "👽", "🧙", "🦊", "🎩", "🌟", "🔮", "💎", "🎯", "🧛", "🦸", "👾", "🐉", "🌸", "⚡"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.12)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // Emoji picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Avatar")
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(emojiOptions, id: \.self) { option in
                                        Text(option)
                                            .font(.system(size: 30))
                                            .padding(8)
                                            .background(
                                                Circle()
                                                    .fill(emoji == option ? Color.cyan.opacity(0.2) : Color.clear)
                                            )
                                            .overlay(
                                                Circle()
                                                    .stroke(emoji == option ? Color.cyan : Color.clear, lineWidth: 2)
                                            )
                                            .onTapGesture { emoji = option }
                                    }
                                }
                            }
                        }

                        // Name
                        inputField("Name", text: $name, placeholder: "e.g. Pirate Captain")

                        // Description
                        inputField("Description", text: $description, placeholder: "e.g. A jolly pirate who rhymes everything")

                        // System prompt
                        VStack(alignment: .leading, spacing: 8) {
                            Text("System Prompt")
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))

                            TextEditor(text: $systemPrompt)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.white)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 120)
                                .padding(14)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Delete button (if editing)
                        if let existing = existingPersona {
                            Button(role: .destructive) {
                                modelContext.delete(existing)
                                try? modelContext.save()
                                onSave?()
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Delete Personality")
                                }
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(existingPersona == nil ? "New Personality" : "Edit Personality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { savePersona() }
                        .foregroundColor(.cyan)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let existing = existingPersona {
                    name = existing.name
                    emoji = existing.emoji
                    description = existing.personalityDescription
                    systemPrompt = existing.systemPrompt
                }
            }
        }
    }

    private func inputField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            TextField(placeholder, text: text)
                .font(.body)
                .foregroundColor(.white)
                .padding(14)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func savePersona() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let prompt = systemPrompt.isEmpty
            ? "You are \(trimmedName). \(description)"
            : systemPrompt

        if let existing = existingPersona {
            existing.name = trimmedName
            existing.emoji = emoji
            existing.personalityDescription = description
            existing.systemPrompt = prompt
        } else {
            let custom = CustomPersonality(
                name: trimmedName,
                emoji: emoji,
                description: description,
                systemPrompt: prompt
            )
            modelContext.insert(custom)
        }

        try? modelContext.save()
        onSave?()
        dismiss()
    }
}
