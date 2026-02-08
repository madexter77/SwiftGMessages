import Foundation
import GMProto
import LinkPresentation
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct ConversationDetailView: View {
    @EnvironmentObject private var model: GMAppModel

    @State private var draftText: String = ""
    @State private var isPickingFile = false

    var body: some View {
        if let conversationID = model.selectedConversationID {
            ZStack {
                IMStyle.chatBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    if model.isSyncingAllMessages, !model.syncProgressText.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(model.syncProgressText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        Divider()
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                HStack {
                                    Button {
                                        Task { await model.loadOlderMessages() }
                                    } label: {
                                        Text("Load Older Messages")
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                    Spacer()
                                }
                                .padding(.top, 8)

                                let isGroupChat = model.conversations.first(where: { $0.conversationID == conversationID })?.isGroupChat ?? false
                                let lastOutgoingID = model.messages.last(where: { $0.hasSenderParticipant && $0.senderParticipant.isMe })?.messageID
                                ForEach(model.messages, id: \.messageID) { msg in
                                    MessageBubbleRow(message: msg, isGroupChat: isGroupChat, lastOutgoingMessageID: lastOutgoingID)
                                        .id(msg.messageID)
                                }

                                if let typing = model.typingIndicatorText {
                                    HStack {
                                        Text(typing)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                        }
                        .onChange(of: model.messages.count) { _, _ in
                            scrollToBottom(proxy: proxy)
                        }
                        .onAppear {
                            scrollToBottom(proxy: proxy)
                        }
                    }

                    Divider()

                    ComposerBar(
                        text: $draftText,
                        onAttach: { isPickingFile = true },
                        onSend: {
                            let toSend = draftText
                            draftText = ""
                            Task { await model.sendMessage(text: toSend) }
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                }
            }
            .navigationTitle(conversationTitle(for: conversationID))
            .onChange(of: draftText) { _, newValue in
                Task { await model.userDraftTextDidChange(newValue) }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        model.copySelectedConversationContext()
                    } label: {
                        Label("Copy Context", systemImage: "doc.on.doc")
                    }

                    Button {
                        Task { await model.refreshConversations() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    Button {
                        Task { await model.syncAllMessagesForSelected() }
                    } label: {
                        Label("Sync All", systemImage: "arrow.down.circle")
                    }

                    Button(role: .destructive) {
                        Task { await model.logout() }
                    } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .fileImporter(
                isPresented: $isPickingFile,
                allowedContentTypes: [.image, .movie, .audio, .pdf, .text, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await model.sendMedia(fileURL: url, caption: nil) }
                case .failure(let error):
                    model.errorMessage = "File import failed: \(error.localizedDescription)"
                }
            }
        } else {
            VStack(spacing: 10) {
                Text("Select a conversation")
                    .font(.headline)
                Text("Pair and sync to start messaging.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func conversationTitle(for id: String) -> String {
        if let conv = model.conversations.first(where: { $0.conversationID == id }) {
            return conv.name.isEmpty ? conv.conversationID : conv.name
        }
        return id
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastID = model.messages.last?.messageID else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}

private struct MessageBubbleRow: View {
    @EnvironmentObject private var model: GMAppModel
    @AppStorage(GMPreferences.linkPreviewsEnabled) private var linkPreviewsEnabled: Bool = true
    @AppStorage(GMPreferences.autoLoadLinkPreviews) private var autoLoadLinkPreviews: Bool = true

    let message: Conversations_Message
    let isGroupChat: Bool
    let lastOutgoingMessageID: String?

    @State private var isHovering = false

    var body: some View {
        let isOutgoing = message.hasSenderParticipant ? message.senderParticipant.isMe : false
        let isLastOutgoing = isOutgoing && (message.messageID == lastOutgoingMessageID)
        let bubbleColor = isOutgoing ? IMStyle.outgoingBubble : IMStyle.incomingBubble
        let textColor: Color = isOutgoing ? .white : .primary
        let senderName = messageSenderName

        HStack(alignment: .bottom, spacing: 10) {
            if isOutgoing { Spacer(minLength: 60) }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                if isGroupChat, !isOutgoing, let senderName {
                    Text(senderName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: 520, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 7) {
                    if let text = messageText, !text.isEmpty {
                        Text(linkedAttributedString(text))
                            .foregroundStyle(textColor)
                            .textSelection(.enabled)
                            .tint(isOutgoing ? .white.opacity(0.95) : IMStyle.outgoingBubble)
                    }

                    if linkPreviewsEnabled, let url = firstURL(in: messageText) {
                        InlineLinkPreview(
                            url: url,
                            isOutgoing: isOutgoing,
                            autoLoad: autoLoadLinkPreviews
                        )
                    }

                    ForEach(mediaItems) { item in
                        if item.isImageLike {
                            InlineImageAttachment(media: item.media, isOutgoing: isOutgoing)
                        } else {
                            AttachmentCard(media: item.media, isOutgoing: isOutgoing)
                        }
                    }
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(bubbleColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    if !isOutgoing {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.secondary.opacity(0.12))
                    }
                }
                .frame(maxWidth: 520, alignment: isOutgoing ? .trailing : .leading)

                if isLastOutgoing, let status = deliveryStatusText {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .frame(maxWidth: 520, alignment: .trailing)
                }

                if !reactionSummaries.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(reactionSummaries, id: \.key) { r in
                            ReactionCapsule(emoji: r.emoji, count: r.count)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: 520, alignment: isOutgoing ? .trailing : .leading)
                }

                #if os(macOS)
                if isHovering {
                    Text(timestampText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .frame(maxWidth: 520, alignment: isOutgoing ? .trailing : .leading)
                        .transition(.opacity)
                }
                #endif
            }

            if !isOutgoing { Spacer(minLength: 60) }
        }
        #if os(macOS)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        #endif
        .contextMenu {
            if let text = messageText, !text.isEmpty {
                Button("Copy Text") {
                    copyToClipboard(text)
                }
            }

            Menu("React") {
                ForEach(["👍", "❤️", "😂", "😮", "😢", "😡"], id: \.self) { emoji in
                    Button(emoji) {
                        Task { await model.react(to: message.messageID, emoji: emoji) }
                    }
                }
            }

            Divider()

            Button("Delete Message", role: .destructive) {
                Task { await model.deleteMessage(messageID: message.messageID) }
            }
        }
    }

    private var messageSenderName: String? {
        guard message.hasSenderParticipant else { return nil }
        let p = message.senderParticipant
        if !p.firstName.isEmpty { return p.firstName }
        if !p.fullName.isEmpty { return p.fullName }
        if !p.formattedNumber.isEmpty { return p.formattedNumber }
        if !p.id.number.isEmpty { return p.id.number }
        if !message.participantID.isEmpty { return message.participantID }
        return nil
    }

    private var messageText: String? {
        for info in message.messageInfo {
            if case .messageContent(let content)? = info.data {
                if !content.content.isEmpty { return content.content }
            }
        }
        return nil
    }

    private var timestampText: String {
        gmDate(from: message.timestamp).formatted(date: .numeric, time: .shortened)
    }

    private var deliveryStatusText: String? {
        let status = message.messageStatus.status
        switch status {
        case .outgoingDisplayed:
            return "Read"
        case .outgoingDelivered:
            return "Delivered"
        case .outgoingComplete:
            return "Sent"
        case .outgoingSending, .outgoingYetToSend, .outgoingValidating, .outgoingResending, .outgoingAwaitingRetry, .outgoingSendAfterProcessing:
            return "Sending..."
        case .outgoingFailedGeneric, .outgoingFailedTooLarge, .outgoingFailedNoRetryNoFallback, .outgoingFailedRecipientLostRcs, .outgoingFailedRecipientLostEncryption, .outgoingFailedRecipientDidNotDecrypt, .outgoingFailedRecipientDidNotDecryptNoMoreRetry:
            return "Failed"
        default:
            return nil
        }
    }

    private var reactionSummaries: [(key: String, emoji: String, count: Int)] {
        var out: [(String, String, Int)] = []
        for (idx, entry) in message.reactions.enumerated() {
            let emoji = entry.data.unicode.isEmpty ? "?" : entry.data.unicode
            let count = max(1, entry.participantIds.count)
            let key = "\(idx)|\(emoji)|\(count)"
            out.append((key, emoji, count))
        }
        return out
    }

    private var mediaItems: [MediaItem] {
        var out: [MediaItem] = []
        out.reserveCapacity(message.messageInfo.count)
        for (idx, info) in message.messageInfo.enumerated() {
            guard case .mediaContent(let media)? = info.data else { continue }

            let id: String
            if info.hasActionMessageID, !info.actionMessageID.isEmpty {
                id = "part:\(info.actionMessageID)"
            } else if !media.mediaID.isEmpty {
                id = "media:\(media.mediaID)"
            } else if !media.thumbnailMediaID.isEmpty {
                id = "thumb:\(media.thumbnailMediaID)"
            } else {
                id = "idx:\(idx)"
            }

            out.append(MediaItem(id: id, media: media))
        }
        return out
    }

    private func copyToClipboard(_ s: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #endif
    }

    private static let urlDetector: NSDataDetector? = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    private func linkedAttributedString(_ text: String) -> AttributedString {
        guard let detector = Self.urlDetector else { return AttributedString(text) }
        let ms = NSMutableAttributedString(string: text)
        let ns = text as NSString
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        for m in matches {
            guard let url = m.url else { continue }
            let scheme = url.scheme?.lowercased()
            guard scheme == "http" || scheme == "https" else { continue }
            ms.addAttribute(.link, value: url, range: m.range)
        }
        return AttributedString(ms)
    }

    private func firstURL(in text: String?) -> URL? {
        guard let text, !text.isEmpty else { return nil }
        guard let detector = Self.urlDetector else { return nil }
        let ns = text as NSString
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        for m in matches {
            guard let url = m.url else { continue }
            let scheme = url.scheme?.lowercased()
            guard scheme == "http" || scheme == "https" else { continue }
            return url
        }
        return nil
    }
}

private struct MediaItem: Identifiable {
    let id: String
    let media: Conversations_MediaContent

    var isImageLike: Bool {
        let mime = media.mimeType.lowercased()
        if mime.hasPrefix("image/") { return true }
        switch media.format {
        case .imageJpeg, .imageJpg, .imagePng, .imageGif, .imageWbmp, .imageXMsBmp, .imageUnspecified:
            return true
        default:
            return false
        }
    }
}

#if os(macOS)
private struct InlineLinkPreview: View {
    @EnvironmentObject private var model: GMAppModel
    @Environment(\.openURL) private var openURL

    let url: URL
    let isOutgoing: Bool
    let autoLoad: Bool

    @State private var metadata: LPLinkMetadata?
    @State private var isLoading = false

    var body: some View {
        Button {
            openURL(url)
        } label: {
            ZStack(alignment: .topLeading) {
                if let metadata {
                    LPLinkViewRepresentable(metadata: metadata)
                        .frame(maxWidth: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    placeholder
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: taskID) {
            guard autoLoad else { return }
            await load()
        }
        .contextMenu {
            Button("Copy URL") {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                #endif
            }
            Button("Open in Browser") { openURL(url) }
        }
    }

    private var taskID: String { url.absoluteString }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isOutgoing ? .white.opacity(0.9) : .secondary)

                Text(url.host ?? "Link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOutgoing ? .white : .primary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            Text(url.absoluteString)
                .font(.caption2)
                .foregroundStyle(isOutgoing ? .white.opacity(0.85) : .secondary)
                .lineLimit(2)

            if !autoLoad {
                Button("Load Preview") {
                    Task { await load() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(isOutgoing ? .white.opacity(0.9) : IMStyle.outgoingBubble)
            }
        }
        .padding(10)
        .frame(maxWidth: 320, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isOutgoing ? Color.white.opacity(0.16) : Color.secondary.opacity(0.12))
        }
    }

    private var cardBackground: Color {
        if isOutgoing {
            return Color.white.opacity(0.14)
        }
        return Color.black.opacity(0.05)
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        metadata = await model.linkMetadata(for: url)
    }
}

private struct LPLinkViewRepresentable: NSViewRepresentable {
    let metadata: LPLinkMetadata

    func makeNSView(context: Context) -> LPLinkView {
        let view = LPLinkView(metadata: metadata)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: LPLinkView, context: Context) {
        // Metadata is set at creation time; no update needed.
    }
}
#endif

#if os(macOS)
private struct InlineImageAttachment: View {
    @EnvironmentObject private var model: GMAppModel
    @AppStorage(GMPreferences.autoLoadImagePreviews) private var autoLoadImagePreviews: Bool = true
    let media: Conversations_MediaContent
    let isOutgoing: Bool

    @State private var image: NSImage?
    @State private var isLoading: Bool = false
    @State private var errorText: String?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 320, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isOutgoing ? Color.white.opacity(0.18) : Color.secondary.opacity(0.14))
                    }
                    .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOutgoing ? Color.white.opacity(0.14) : Color.black.opacity(0.06))
                    .frame(maxWidth: 320, minHeight: 160, maxHeight: 260)
                    .overlay {
                        VStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                            } else {
                                Image(systemName: errorText == nil ? "arrow.down.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(isOutgoing ? .white.opacity(0.9) : .secondary)
                            }

                            Text(errorText ?? "Loading attachment...")
                                .font(.caption)
                                .foregroundStyle(isOutgoing ? .white.opacity(0.9) : .secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .frame(maxWidth: 260)
                        }
                        .padding(.vertical, 18)
                        .padding(.horizontal, 14)
                    }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            Task { await load(preferThumbnail: false) }
        }
        .task(id: taskID) {
            guard autoLoadImagePreviews else { return }
            await load(preferThumbnail: true)
        }
    }

    private var taskID: String {
        // Stable enough for view lifecycle; real caching is done on disk by the model.
        let full = media.mediaID
        let thumb = media.thumbnailMediaID
        let inlineCount = media.mediaData.count
        return "\(full)|\(thumb)|\(inlineCount)|\(media.mimeType)|\(media.mediaName)|\(media.size)"
    }

    private func load(preferThumbnail: Bool) async {
        // Keep whatever image we have already; just avoid parallel downloads.
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let url = try await model.ensureAttachmentFileURL(media, preferThumbnail: preferThumbnail)
            let loaded = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value

            if let loaded {
                image = loaded
                errorText = nil
            } else {
                errorText = "Couldn't decode image"
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
#endif

private struct AttachmentCard: View {
    @EnvironmentObject private var model: GMAppModel
    let media: Conversations_MediaContent
    let isOutgoing: Bool

    var body: some View {
        Button {
            Task { await model.downloadAndOpenMedia(media) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOutgoing ? .white.opacity(0.95) : .secondary)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(media.mediaName.isEmpty ? "Attachment" : media.mediaName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isOutgoing ? .white : .primary)
                        .lineLimit(1)

                    if !subtitleText.isEmpty {
                        Text(subtitleText)
                            .font(.caption2)
                            .foregroundStyle(isOutgoing ? .white.opacity(0.85) : .secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isOutgoing ? .white.opacity(0.95) : .secondary)
            }
            .padding(10)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var subtitleText: String {
        var parts: [String] = []
        if !media.mimeType.isEmpty { parts.append(media.mimeType) }
        if media.size > 0 { parts.append(ByteCountFormatter.string(fromByteCount: media.size, countStyle: .file)) }
        return parts.joined(separator: "  ")
    }

    private var cardBackground: Color {
        if isOutgoing {
            return Color.white.opacity(0.18)
        }
        return Color.black.opacity(0.06)
    }

    private var iconName: String {
        let mime = media.mimeType.lowercased()
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("video/") { return "video" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime == "application/pdf" { return "doc.richtext" }
        return "doc"
    }
}

private struct ReactionCapsule: View {
    let emoji: String
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(emoji)
            if count > 1 {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(.secondary.opacity(0.12))
        }
    }
}

private struct ComposerBar: View {
    @Binding var text: String
    let onAttach: () -> Void
    let onSend: () -> Void

    var body: some View {
        let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        HStack(alignment: .bottom, spacing: 10) {
            Button {
                onAttach()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Attach a file")

            TextField("iMessage", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(IMStyle.incomingBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.secondary.opacity(0.12))
                }

            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(canSend ? IMStyle.outgoingBubble : .secondary.opacity(0.35))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!canSend)
        }
    }
}
