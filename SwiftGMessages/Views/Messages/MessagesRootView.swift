import GMProto
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct MessagesRootView: View {
    @EnvironmentObject private var model: GMAppModel

    @State private var searchText: String = ""
    @State private var showingNewMessageSheet = false
    @State private var showingSettingsSheet = false

    private var filteredConversations: [Conversations_Conversation] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return model.conversations }
        return model.conversations.filter { conv in
            let name = conv.name.isEmpty ? conv.conversationID : conv.name
            let preview = conv.latestMessage.displayContent
            return name.localizedCaseInsensitiveContains(q) || preview.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: {
                model.selectedConversationID
            }, set: { newValue in
                Task { await model.selectConversation(newValue) }
            })) {
                ForEach(filteredConversations, id: \.conversationID) { conv in
                    ConversationRow(conversation: conv)
                        .tag(conv.conversationID)
                }
            }
            .navigationTitle("Messages")
            .searchable(text: $searchText, placement: .sidebar)
            .listStyle(.sidebar)
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                            .accessibilityLabel("Settings")
                    }
                }
                #endif

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewMessageSheet = true
                    } label: {
                        Label("New Message", systemImage: "square.and.pencil")
                    }
                }
            }
        } detail: {
            ConversationDetailView()
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingNewMessageSheet) {
            NewConversationSheet(isPresented: $showingNewMessageSheet)
        }
        #if os(iOS)
        .sheet(isPresented: $showingSettingsSheet) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showingSettingsSheet = false
                            }
                        }
                    }
            }
        }
        #endif
    }
}

private struct ConversationRow: View {
    @EnvironmentObject private var model: GMAppModel
    let conversation: Conversations_Conversation

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AvatarView(title: conversationTitle, hexColor: conversation.avatarHexColor, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(conversationTitle)
                        .font(.system(size: 14, weight: conversation.unread ? .semibold : .regular))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(timestampText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    if conversation.unread {
                        Circle()
                            .fill(Color(red: 0.0, green: 0.48, blue: 1.0))
                            .frame(width: 7, height: 7)
                            .padding(.leading, 2)
                    }
                }

                Text(previewText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy Conversation ID") {
                copyToClipboard(conversation.conversationID)
            }

            Divider()

            if conversation.status == .archived || conversation.status == .keepArchived {
                Button("Unarchive") {
                    Task { await model.setConversationArchived(conversationID: conversation.conversationID, archived: false) }
                }
            } else {
                Button("Archive") {
                    Task { await model.setConversationArchived(conversationID: conversation.conversationID, archived: true) }
                }
            }
        }
    }

    private var conversationTitle: String {
        conversation.name.isEmpty ? conversation.conversationID : conversation.name
    }

    private var previewText: String {
        var s = conversation.latestMessage.displayContent
        if s.isEmpty { s = "(no messages)" }
        if conversation.latestMessage.fromMe != 0 {
            s = "You: " + s
        }
        return s
    }

    private var timestampText: String {
        let d = gmDate(from: conversation.lastMessageTimestamp)
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    private func copyToClipboard(_ s: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #endif
    }
}
