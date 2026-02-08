import Foundation
import GMProto
import LinkPresentation
import SwiftUI
import UniformTypeIdentifiers

#if canImport(AVFoundation)
import AVFoundation
#endif

#if os(macOS)
import AppKit
#endif

struct ConversationDetailView: View {
    @EnvironmentObject private var model: GMAppModel

    private let bottomAnchorID = "gm-conversation-bottom-anchor"
    private let bottomComposerClearance: CGFloat = 52

    @State private var draftText: String = ""
    @State private var isPickingFile = false
    @State private var didInitialScrollConversationID: String?
    @State private var isRecordingVoice = false
    @State private var voiceRecordingFileURL: URL?
    #if canImport(AVFoundation)
    @State private var voiceRecorder: AVAudioRecorder?
    #endif

    var body: some View {
        if let conversationID = model.selectedConversationID {
            let messageCount = model.messages.count
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
                        GeometryReader { scrollGeometry in
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

                                    Color.clear
                                        .frame(height: bottomComposerClearance)

                                    Color.clear
                                        .frame(height: 1)
                                        .id(bottomAnchorID)
                                }
                                .padding(.horizontal, 14)
                                .padding(.bottom, 10)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: scrollGeometry.size.height, alignment: .bottom)
                            }
                            .defaultScrollAnchor(.bottom)
                            .onAppear {
                                scrollToBottomIfNeeded(proxy: proxy, conversationID: conversationID)
                            }
                            .onChange(of: conversationID) { _, newConversationID in
                                scrollToBottomIfNeeded(proxy: proxy, conversationID: newConversationID)
                            }
                            .onChange(of: messageCount) { _, _ in
                                scrollToBottomIfNeeded(proxy: proxy, conversationID: conversationID)
                            }
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                ComposerBar(
                    text: $draftText,
                    isRecordingVoice: isRecordingVoice,
                    onAttach: { isPickingFile = true },
                    onSend: sendDraftMessage,
                    onVoiceAction: { Task { await toggleVoiceRecording() } }
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }
            .navigationTitle(conversationTitle(for: conversationID))
            .onDisappear {
                Task { await stopVoiceRecording(send: false) }
            }
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

    private func sendDraftMessage() {
        let toSend = draftText
        draftText = ""
        Task { await model.sendMessage(text: toSend) }
    }

    @MainActor
    private func toggleVoiceRecording() async {
        if isRecordingVoice {
            await stopVoiceRecording(send: true)
        } else {
            await startVoiceRecording()
        }
    }

    @MainActor
    private func startVoiceRecording() async {
        #if canImport(AVFoundation)
        guard await requestMicrophonePermissionIfNeeded() else {
            if model.errorMessage == nil || model.errorMessage?.isEmpty == true {
                model.errorMessage = "Microphone permission was denied."
            }
            return
        }

        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            #endif

            let recordingsDir = FileManager.default.temporaryDirectory.appendingPathComponent("voice-recordings", isDirectory: true)
            try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
            let fileURL = recordingsDir.appendingPathComponent("voice-\(UUID().uuidString).m4a")

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            guard recorder.prepareToRecord(), recorder.record() else {
                throw NSError(
                    domain: "SwiftGMessages",
                    code: 6001,
                    userInfo: [NSLocalizedDescriptionKey: "Recorder failed to start."]
                )
            }

            voiceRecorder = recorder
            voiceRecordingFileURL = fileURL
            isRecordingVoice = true
            model.errorMessage = nil
        } catch {
            model.errorMessage = "Failed to start voice recording: \(error.localizedDescription)"
            await stopVoiceRecording(send: false)
        }
        #else
        model.errorMessage = "Voice recording isn't available on this platform."
        #endif
    }

    @MainActor
    private func stopVoiceRecording(send: Bool) async {
        #if canImport(AVFoundation)
        voiceRecorder?.stop()
        voiceRecorder = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        #endif

        isRecordingVoice = false

        guard let fileURL = voiceRecordingFileURL else { return }
        voiceRecordingFileURL = nil

        if !send {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileSize > 0 else {
            model.errorMessage = "Voice recording was empty."
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        await model.sendMedia(fileURL: fileURL, caption: nil)
        try? FileManager.default.removeItem(at: fileURL)
    }

    @MainActor
    private func requestMicrophonePermissionIfNeeded() async -> Bool {
        #if canImport(AVFoundation)
        #if os(iOS)
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            model.errorMessage = "Missing NSMicrophoneUsageDescription in app configuration."
            return false
        }

        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #elseif os(macOS)
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            model.errorMessage = "Missing NSMicrophoneUsageDescription in app configuration."
            return false
        }

        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        return false
        #endif
        #else
        return false
        #endif
    }

    private func conversationTitle(for id: String) -> String {
        if let conv = model.conversations.first(where: { $0.conversationID == id }) {
            return conv.name.isEmpty ? conv.conversationID : conv.name
        }
        return id
    }

    private func scrollToBottomIfNeeded(proxy: ScrollViewProxy, conversationID: String) {
        guard model.selectedConversationID == conversationID else { return }

        let isInitialScroll = didInitialScrollConversationID != conversationID
        let performScroll = {
            guard model.selectedConversationID == conversationID else { return }
            let didScroll = scrollToBottom(proxy: proxy, animated: !isInitialScroll)
            if didScroll, isInitialScroll {
                didInitialScrollConversationID = conversationID
            }
        }
        performScroll()

        if isInitialScroll {
            // One additional pass catches cases where layout finalizes after onAppear.
            DispatchQueue.main.async(execute: performScroll)
        }
    }

    @discardableResult
    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) -> Bool {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }

        return true
    }
}

private struct MessageBubbleRow: View {
    @EnvironmentObject private var model: GMAppModel
    @AppStorage(GMPreferences.linkPreviewsEnabled) private var linkPreviewsEnabled: Bool = true
    @AppStorage(GMPreferences.autoLoadLinkPreviews) private var autoLoadLinkPreviews: Bool = true

    let message: Conversations_Message
    let isGroupChat: Bool
    let lastOutgoingMessageID: String?

    @State private var isShowingDetails = false

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

                    #if os(macOS)
                    if linkPreviewsEnabled, let url = firstURL(in: messageText) {
                        InlineLinkPreview(
                            url: url,
                            isOutgoing: isOutgoing,
                            autoLoad: autoLoadLinkPreviews
                        )
                    }
                    #endif

                    ForEach(mediaItems) { item in
                        #if os(macOS)
                        if item.isImageLike {
                            InlineImageAttachment(media: item.media, isOutgoing: isOutgoing)
                        } else {
                            AttachmentCard(media: item.media, isOutgoing: isOutgoing)
                        }
                        #else
                        AttachmentCard(media: item.media, isOutgoing: isOutgoing)
                        #endif
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
                if isShowingDetails {
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
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) {
                isShowingDetails.toggle()
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
    let isRecordingVoice: Bool
    let onAttach: () -> Void
    let onSend: () -> Void
    let onVoiceAction: () -> Void

    var body: some View {
        let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        HStack(alignment: .center, spacing: 10) {
            Button {
                onAttach()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.white.opacity(0.16)).interactive(), in: Circle())
            .help("Attach a file")

            HStack(alignment: .center, spacing: 8) {
                TextField("Message", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .font(.system(size: 15))
                    .padding(.leading, 11)
                    .padding(.vertical, 7)

                if canSend {
                    Button {
                        onSend()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background {
                                Circle()
                                    .fill(IMStyle.outgoingBubble)
                            }
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityLabel("Send message")
                } else {
                    Button {
                        onVoiceAction()
                    } label: {
                        Image(systemName: isRecordingVoice ? "stop.fill" : "waveform")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isRecordingVoice ? Color.red : Color.secondary)
                            .frame(width: 24, height: 24, alignment: .center)
                            .background {
                                if isRecordingVoice {
                                    Circle()
                                        .fill(Color.red.opacity(0.14))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isRecordingVoice ? "Stop recording and send voice message" : "Record voice message")
                }
            }
            .padding(.trailing, 6)
            .frame(minHeight: 36)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
    }
}

@MainActor
private enum ConversationDetailPreviewFactory {
    static func populatedModel() -> GMAppModel {
        let model = GMAppModel()
        let now = unixMillis(Date())
        let conversation = makeConversation(now: now)

        model.screen = .ready
        model.conversations = [conversation]
        model.selectedConversationID = conversation.conversationID
        model.messages = makeMessages(conversationID: conversation.conversationID, now: now)
        model.typingIndicatorText = "Maya is typing..."
        model.isSyncingAllMessages = true
        model.syncProgressText = "Syncing 24 of 80 messages..."
        return model
    }

    static func emptySelectionModel() -> GMAppModel {
        let model = GMAppModel()
        model.screen = .ready
        model.conversations = [makeConversation(now: unixMillis(Date()))]
        model.selectedConversationID = nil
        model.messages = []
        model.typingIndicatorText = nil
        model.isSyncingAllMessages = false
        model.syncProgressText = ""
        return model
    }

    private static func makeConversation(now: Int64) -> Conversations_Conversation {
        var conversation = Conversations_Conversation()
        conversation.conversationID = "preview-conversation"
        conversation.name = "UI Design Crew"
        conversation.isGroupChat = true
        conversation.avatarHexColor = "#1485FF"
        conversation.lastMessageTimestamp = now
        conversation.latestMessageID = "message-24"
        conversation.latestMessage.displayContent = "Now it behaves like Messages from the bottom."
        conversation.latestMessage.displayName = "Me"
        conversation.latestMessage.fromMe = 1
        conversation.defaultOutgoingID = "me"

        var me = Conversations_Participant()
        me.id.number = "me"
        me.isMe = true
        me.firstName = "Me"
        conversation.participants = [me]

        return conversation
    }

    private static func makeMessages(conversationID: String, now: Int64) -> [Conversations_Message] {
        let transcript: [(senderName: String, isMe: Bool, text: String, status: Conversations_MessageStatusType?)] = [
            ("Maya", false, "Can we tighten up the vertical spacing in the composer?", nil),
            ("Me", true, "Yep. I also want to tune the bubble corner radius on iOS.", .outgoingDelivered),
            ("Alex", false, "Let's verify both compact and regular layouts in previews.", nil),
            ("Maya", false, "Also check pointer hover states on macOS.", nil),
            ("Me", true, "I switched the field to a single capsule and removed stacked layers.", .outgoingDelivered),
            ("Alex", false, "Great. Did we keep the placeholder generic?", nil),
            ("Me", true, "Yes, it now says Message.", .outgoingDelivered),
            ("Maya", false, "Can we make the bar slightly smaller?", nil),
            ("Me", true, "Done. Reduced height and inner padding.", .outgoingDelivered),
            ("Alex", false, "How does it behave with many messages?", nil),
            ("Me", true, "Auto-scroll tracks new items, but I want to harden initial placement.", .outgoingDelivered),
            ("Maya", false, "Perfect, start from the latest like Messages.", nil),
            ("Me", true, "Implemented bottom anchoring plus scroll after first layout pass.", .outgoingDelivered),
            ("Alex", false, "Nice. Let's keep this as the default preview thread.", nil),
            ("Maya", false, "Looks good in both iPhone and Mac widths.", nil),
            ("Me", true, "Final tweak looks right. Shipping.", .outgoingDisplayed),
            ("Alex", false, "Can we stress it with an even longer thread preview?", nil),
            ("Me", true, "Added more rows so both platforms show realistic scroll behavior.", .outgoingDelivered),
            ("Maya", false, "Does it start at the latest message now?", nil),
            ("Me", true, "Yes. We anchor to bottom and keep new messages pinned there.", .outgoingDelivered),
            ("Alex", false, "Great. That should feel like native Messages.", nil),
            ("Me", true, "Now it behaves like Messages from the bottom.", .outgoingDisplayed),
            ("Maya", false, "Ship it.", nil),
            ("Me", true, "Done.", .outgoingDisplayed),
        ]

        let firstTimestamp = now - Int64(transcript.count - 1) * 95_000
        return transcript.enumerated().map { idx, entry in
            makeTextMessage(
                id: "message-\(idx + 1)",
                conversationID: conversationID,
                senderName: entry.senderName,
                isMe: entry.isMe,
                text: entry.text,
                timestamp: firstTimestamp + Int64(idx) * 95_000,
                status: entry.status
            )
        }
    }

    private static func makeTextMessage(
        id: String,
        conversationID: String,
        senderName: String,
        isMe: Bool,
        text: String,
        timestamp: Int64,
        status: Conversations_MessageStatusType? = nil
    ) -> Conversations_Message {
        var message = Conversations_Message()
        message.messageID = id
        message.conversationID = conversationID
        message.timestamp = timestamp
        message.participantID = isMe ? "me" : senderName.lowercased()

        var participant = Conversations_Participant()
        participant.isMe = isMe
        participant.firstName = senderName
        participant.fullName = senderName
        message.senderParticipant = participant

        var messageInfo = Conversations_MessageInfo()
        var messageContent = Conversations_MessageContent()
        messageContent.content = text
        messageInfo.messageContent = messageContent
        message.messageInfo = [messageInfo]

        if let status {
            var messageStatus = Conversations_MessageStatus()
            messageStatus.status = status
            message.messageStatus = messageStatus
        }

        return message
    }

    private static func unixMillis(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000)
    }
}

@MainActor
private struct ConversationDetailPreviewHost: View {
    @StateObject private var model: GMAppModel

    init(model: GMAppModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            ConversationDetailView()
        }
        .environmentObject(model)
    }
}

#Preview("macOS - Conversation") {
    ConversationDetailPreviewHost(model: ConversationDetailPreviewFactory.populatedModel())
        .frame(width: 1_050, height: 700)
}

#Preview("iOS - Conversation") {
    ConversationDetailPreviewHost(model: ConversationDetailPreviewFactory.populatedModel())
        .frame(width: 393, height: 852)
}

#Preview("macOS - Empty State") {
    ConversationDetailPreviewHost(model: ConversationDetailPreviewFactory.emptySelectionModel())
        .frame(width: 1_050, height: 700)
}

#Preview("iOS - Empty State") {
    ConversationDetailPreviewHost(model: ConversationDetailPreviewFactory.emptySelectionModel())
        .frame(width: 393, height: 852)
}
