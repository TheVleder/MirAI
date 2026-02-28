import SwiftUI
import SwiftData

/// List of all conversations with create, rename, delete, and search.
struct ConversationListView: View {

    @Environment(ConversationManager.self) private var conversationManager
    @Environment(LLMManager.self) private var llm
    @Environment(ModelDownloader.self) private var downloader

    @State private var conversations: [Conversation] = []
    @State private var searchText: String = ""
    @State private var showSettings = false
    @State private var showDeleteConfirmation = false
    @State private var conversationToDelete: Conversation?
    @State private var editingConversation: Conversation?
    @State private var renameText: String = ""
    @State private var navigateToChat = false
    @State private var showModelDeleteConfirm = false

    var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.messages.contains { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.12)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if conversations.isEmpty {
                        emptyState
                    } else {
                        conversationList
                    }
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search conversations…")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(role: .destructive) {
                            showModelDeleteConfirm = true
                        } label: {
                            Label("Delete Model", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.white.opacity(0.7))
                        }

                        Button { createNewConversation() } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(.cyan)
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $navigateToChat) {
                ChatView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .alert("Delete Model", isPresented: $showModelDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    llm.unloadModel()
                    downloader.deleteCurrentModel()
                }
            } message: {
                Text("This will delete the downloaded model and free storage. You'll return to the download screen.")
            }
            .alert("Rename Conversation", isPresented: Binding(
                get: { editingConversation != nil },
                set: { if !$0 { editingConversation = nil } }
            )) {
                TextField("Title", text: $renameText)
                Button("Cancel", role: .cancel) { editingConversation = nil }
                Button("Save") {
                    if let conv = editingConversation {
                        conversationManager.rename(conv, to: renameText)
                        refreshList()
                    }
                    editingConversation = nil
                }
            } message: {
                Text("Enter a new name for this conversation.")
            }
            .onAppear { refreshList() }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundColor(.white.opacity(0.12))

            Text("No conversations yet")
                .font(.system(.title3, design: .rounded, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            Text("Tap + to start your first conversation with MirAI")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)

            Button {
                createNewConversation()
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("New Conversation")
                }
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [.cyan, .blue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        List {
            ForEach(filteredConversations) { conversation in
                Button {
                    conversationManager.activeConversation = conversation
                    llm.resetConversation()
                    navigateToChat = true
                } label: {
                    conversationRow(conversation)
                }
                .listRowBackground(Color.white.opacity(0.03))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        conversationManager.delete(conversation)
                        refreshList()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        renameText = conversation.title
                        editingConversation = conversation
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
                .contextMenu {
                    Button {
                        renameText = conversation.title
                        editingConversation = conversation
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        conversationManager.delete(conversation)
                        refreshList()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        HStack(spacing: 14) {
            // Personality emoji
            let personality = Personality.find(conversation.personalityID)
            Text(personality.emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.06))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(conversation.messages.count) messages")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.35))

                    Text("·")
                        .foregroundColor(.white.opacity(0.2))

                    Text(conversation.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.white.opacity(0.2))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func createNewConversation() {
        conversationManager.createConversation(personalityID: llm.activePersonality.id)
        llm.resetConversation()
        refreshList()
        navigateToChat = true
    }

    private func refreshList() {
        conversations = conversationManager.fetchAll()
    }
}
