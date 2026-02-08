import Foundation
import Combine
import CryptoKit
import LibGM
import GMProto
import LinkPresentation
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

@MainActor
final class GMAppModel: ObservableObject {
    enum Screen {
        case loading
        case needsPairing
        case pairing
        case ready
    }

    @Published var screen: Screen = .loading

    @Published var connectionStatusText: String = ""
    @Published var errorMessage: String?

    // Pairing
    @Published var pairingQRCodeURL: String?
    @Published var pairingStatusText: String = ""

    // Main UI
    @Published var conversations: [Conversations_Conversation] = []
    @Published var selectedConversationID: String?
    @Published var messages: [Conversations_Message] = []

    @Published var typingIndicatorText: String?
    @Published var isSyncingAllMessages: Bool = false
    @Published var syncProgressText: String = ""

    @Published var phoneSettings: Settings_Settings?

    private let store: AuthDataStore
    private let eventHandler: GMEventStreamHandler
    private let cache: GMCacheStore

    private var client: GMClient?
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var refreshConversationsTask: Task<Void, Never>?
    private var refreshMessagesTask: Task<Void, Never>?

    private var messagesCursor: Client_Cursor?

    private var notifiedMessageIDs: Set<String> = []

    private var markReadTask: Task<Void, Never>?
    private var lastMarkedReadByConversation: [String: String] = [:]

    private var outgoingTypingStopTask: Task<Void, Never>?
    private var outgoingTypingGeneration: UInt64 = 0
    private var outgoingTypingConversationID: String?
    private var outgoingTypingLastSentAt: Date = .distantPast
    private var outgoingTypingIsActive: Bool = false

    private var remoteTypingClearTask: Task<Void, Never>?

    private var linkMetadataMemory: [String: LPLinkMetadata] = [:]
    private var linkMetadataTasks: [String: Task<LPLinkMetadata?, Never>] = [:]
    private var linkPrefetchTask: Task<Void, Never>?

    private static let lastSelectedConversationKey = "gm_last_selected_conversation_id"

    init(store: AuthDataStore? = nil) {
        GMPreferences.registerDefaults()
        self.store = store ?? Self.makeDefaultStore()
        self.eventHandler = GMEventStreamHandler()
        self.cache = GMCacheStore(rootURL: self.store.directory.appendingPathComponent("Cache", isDirectory: true))
        GMLog.info(.app, "Init storeDir=\(self.store.directory.path)")
    }

    nonisolated static func makeDefaultStore() -> AuthDataStore {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("SwiftGMessages", isDirectory: true)
        return AuthDataStore(directoryURL: dir)
    }

    func start() async {
        guard eventTask == nil else { return }

        connectionStatusText = "Starting..."
        GMLog.info(.app, "Start (store.exists=\(store.exists))")

        // Load cached data first so the UI can render instantly while networking happens.
        if store.exists {
            if let cachedConvs = await cache.loadConversations() {
                conversations = cachedConvs.sorted(by: { $0.lastMessageTimestamp > $1.lastMessageTimestamp })
                if let first = conversations.first {
                    GMLog.info(.cache, "Loaded conversations cache count=\(conversations.count) sample.lastMessageTimestamp=\(describeTimestamp(first.lastMessageTimestamp))")
                } else {
                    GMLog.info(.cache, "Loaded conversations cache count=0")
                }
            }

            let savedID = UserDefaults.standard.string(forKey: Self.lastSelectedConversationKey)
            if let savedID, conversations.contains(where: { $0.conversationID == savedID }) {
                selectedConversationID = savedID
            } else {
                selectedConversationID = conversations.first?.conversationID
            }

            if let conversationID = selectedConversationID,
               let cachedMessages = await cache.loadMessages(conversationID: conversationID)
            {
                messages = cachedMessages.messages.sorted(by: { $0.timestamp < $1.timestamp })
                messagesCursor = cachedMessages.cursor
                if let last = messages.last {
                    GMLog.info(.cache, "Loaded messages cache conv=\(shortID(conversationID)) count=\(messages.count) sample.last.timestamp=\(describeTimestamp(last.timestamp)) cursor=\(messagesCursor != nil ? "yes" : "no")")
                } else {
                    GMLog.info(.cache, "Loaded messages cache conv=\(shortID(conversationID)) count=0 cursor=\(messagesCursor != nil ? "yes" : "no")")
                }
            }
        }

        let stream = await eventHandler.makeStream(bufferingPolicy: .bufferingNewest(1024))
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in stream {
                await self.handle(event)
            }
        }

        do {
            if let loaded = try await GMClient.loadFromStore(
                store,
                eventHandler: eventHandler,
                autoReconnectAfterPairing: false
            ) {
                client = loaded
                screen = .ready
                GMLog.info(.app, "Loaded auth from store, bootstrapping")
                try await connectAndBootstrap()
            } else {
                screen = .needsPairing
                connectionStatusText = ""
                GMLog.info(.app, "No auth in store; needs pairing")
            }
        } catch {
            screen = .needsPairing
            connectionStatusText = ""
            errorMessage = "Failed to load auth: \(error.localizedDescription)"
            GMLog.error(.app, "Failed to load auth: \(error.localizedDescription)")
        }
    }

    func startPairing() async {
        errorMessage = nil
        typingIndicatorText = nil

        pairingQRCodeURL = nil
        pairingStatusText = "Requesting QR code..."
        connectionStatusText = ""
        screen = .pairing
        GMLog.info(.app, "Start pairing")

        let newClient = await GMClient(eventHandler: eventHandler, autoReconnectAfterPairing: false)
        client = newClient

        do {
            let qr = try await newClient.startLogin()
            pairingQRCodeURL = qr
            pairingStatusText = "Scan this QR code in Google Messages on your phone."
            GMLog.info(.app, "Pairing QR received urlLen=\(qr.count)")

            // Ensure the long-poll stream is open so we don't miss the paired event.
            try await newClient.connect()
            pairingStatusText = "Waiting for phone to pair..."
            GMLog.info(.app, "Connected for pairing; waiting for phone")
        } catch {
            screen = .needsPairing
            pairingStatusText = ""
            errorMessage = "Pairing failed: \(error.localizedDescription)"
            GMLog.error(.app, "Pairing failed: \(error.localizedDescription)")
        }
    }

    func logout() async {
        errorMessage = nil
        pairingQRCodeURL = nil
        pairingStatusText = ""
        typingIndicatorText = nil
        GMLog.info(.app, "Logout")

        isSyncingAllMessages = false
        syncProgressText = ""

        markReadTask?.cancel()
        markReadTask = nil
        outgoingTypingStopTask?.cancel()
        outgoingTypingStopTask = nil
        outgoingTypingIsActive = false
        outgoingTypingConversationID = nil
        remoteTypingClearTask?.cancel()
        remoteTypingClearTask = nil
        notifiedMessageIDs.removeAll(keepingCapacity: false)
        linkPrefetchTask?.cancel()
        linkPrefetchTask = nil
        linkMetadataTasks.values.forEach { $0.cancel() }
        linkMetadataTasks.removeAll(keepingCapacity: false)
        linkMetadataMemory.removeAll(keepingCapacity: false)

        refreshConversationsTask?.cancel()
        refreshConversationsTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        refreshMessagesTask?.cancel()
        refreshMessagesTask = nil

        messages = []
        messagesCursor = nil
        conversations = []
        selectedConversationID = nil

        if let client {
            await client.disconnect()
        }
        client = nil

        do {
            try store.delete()
        } catch {
            // Ignore delete errors; the user can retry.
        }

        UserDefaults.standard.removeObject(forKey: Self.lastSelectedConversationKey)
        await cache.clearAll()
        GMLog.info(.cache, "Cache cleared")

        screen = .needsPairing
        connectionStatusText = ""
    }

    func refreshConversations() async {
        guard let client else { return }
        GMLog.debug(.network, "Refreshing conversations (network)")
        do {
            let convs = try await client.listConversations(count: 75)
            conversations = convs.sorted(by: { $0.lastMessageTimestamp > $1.lastMessageTimestamp })
            await cache.saveConversations(conversations)
            if let first = conversations.first {
                GMLog.info(.network, "Refreshed conversations count=\(conversations.count) sample.lastMessageTimestamp=\(describeTimestamp(first.lastMessageTimestamp))")
            } else {
                GMLog.info(.network, "Refreshed conversations count=0")
            }

            if selectedConversationID == nil {
                let savedID = UserDefaults.standard.string(forKey: Self.lastSelectedConversationKey)
                if let savedID, conversations.contains(where: { $0.conversationID == savedID }) {
                    selectedConversationID = savedID
                } else {
                    selectedConversationID = conversations.first?.conversationID
                }
                await loadMessagesForSelected(reset: true, forceNetwork: false)
            }
        } catch {
            errorMessage = "Failed to refresh conversations: \(error.localizedDescription)"
            GMLog.error(.network, "Failed to refresh conversations: \(error.localizedDescription)")
        }
    }

    func selectConversation(_ id: String?) async {
        guard selectedConversationID != id else { return }
        await stopOutgoingTypingIfNeeded()
        linkPrefetchTask?.cancel()
        linkPrefetchTask = nil
        remoteTypingClearTask?.cancel()
        remoteTypingClearTask = nil
        typingIndicatorText = nil

        selectedConversationID = id
        GMLog.info(.app, "Select conversation conv=\(id.map(shortID) ?? "nil")")

        if let id {
            UserDefaults.standard.set(id, forKey: Self.lastSelectedConversationKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.lastSelectedConversationKey)
        }

        // Cancel any in-flight message refresh for the previous selection.
        refreshMessagesTask?.cancel()
        refreshMessagesTask = nil

        await loadMessagesForSelected(reset: true, forceNetwork: false)
    }

    func loadMessagesForSelected(reset: Bool, forceNetwork: Bool) async {
        guard let client, let conversationID = selectedConversationID else { return }
        GMLog.debug(.network, "Load messages conv=\(shortID(conversationID)) reset=\(reset) forceNetwork=\(forceNetwork)")

        if reset {
            messages = []
            messagesCursor = nil

            if let cached = await cache.loadMessages(conversationID: conversationID) {
                messages = cached.messages.sorted(by: { $0.timestamp < $1.timestamp })
                messagesCursor = cached.cursor
                GMLog.info(.cache, "Cache hit messages conv=\(shortID(conversationID)) count=\(messages.count) cursor=\(messagesCursor != nil ? "yes" : "no")")

                // For fast switching, don't hit the network if we already have a cache.
                if !forceNetwork {
                    GMLog.info(.cache, "Skipping network for conv=\(shortID(conversationID)) (cached)")
                    scheduleMarkReadForSelectedIfNeeded(reason: "cache_hit")
                    scheduleLinkPreviewPrefetchIfNeeded(messages: messages)
                    return
                }
            } else {
                GMLog.info(.cache, "Cache miss messages conv=\(shortID(conversationID))")
            }
        }

        do {
            let cursorToUse = reset ? nil : messagesCursor
            let (page, cursor) = try await client.fetchMessages(
                conversationID: conversationID,
                count: 75,
                cursor: cursorToUse
            )
            if let first = page.first, let last = page.last {
                GMLog.info(.network, "Fetched messages conv=\(shortID(conversationID)) pageCount=\(page.count) first.ts=\(describeTimestamp(first.timestamp)) last.ts=\(describeTimestamp(last.timestamp)) cursor=\(cursor != nil ? "yes" : "no")")
            } else {
                GMLog.info(.network, "Fetched messages conv=\(shortID(conversationID)) pageCount=\(page.count) cursor=\(cursor != nil ? "yes" : "no")")
            }

            messages = mergeMessages(existing: messages, incoming: page)

            messages.sort(by: { $0.timestamp < $1.timestamp })
            if reset {
                // Preserve an older cursor if we already had one from a deeper sync.
                if messagesCursor == nil {
                    messagesCursor = cursor
                }
            } else {
                messagesCursor = cursor
            }

            await cache.saveMessages(conversationID: conversationID, messages: messages, cursor: messagesCursor)
            scheduleMarkReadForSelectedIfNeeded(reason: "messages_loaded")
            scheduleLinkPreviewPrefetchIfNeeded(messages: messages)
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
            GMLog.error(.network, "Failed to load messages conv=\(shortID(conversationID)): \(error.localizedDescription)")
        }
    }

    func loadOlderMessages() async {
        guard messagesCursor != nil else { return }
        GMLog.info(.app, "Load older messages conv=\(selectedConversationID.map(shortID) ?? "nil")")
        await loadMessagesForSelected(reset: false, forceNetwork: true)
    }

    func userDraftTextDidChange(_ text: String) async {
        guard UserDefaults.standard.bool(forKey: GMPreferences.sendTypingIndicators) else { return }
        guard let client, let conversationID = selectedConversationID else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        outgoingTypingGeneration &+= 1
        let generation = outgoingTypingGeneration

        outgoingTypingStopTask?.cancel()
        outgoingTypingStopTask = nil

        // If the draft becomes empty, stop typing immediately.
        if trimmed.isEmpty {
            await stopOutgoingTypingIfNeeded()
            return
        }

        // Reset the idle timer on each edit.
        outgoingTypingStopTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            if self.outgoingTypingGeneration == generation {
                await self.stopOutgoingTypingIfNeeded()
            }
        }

        let now = Date()
        let minInterval: TimeInterval = 2.0
        let shouldSendStart =
            !outgoingTypingIsActive ||
            outgoingTypingConversationID != conversationID ||
            now.timeIntervalSince(outgoingTypingLastSentAt) > minInterval

        guard shouldSendStart else { return }

        do {
            try await client.setTyping(conversationID: conversationID, isTyping: true)
            outgoingTypingIsActive = true
            outgoingTypingConversationID = conversationID
            outgoingTypingLastSentAt = now
            GMLog.debug(.network, "Typing start conv=\(shortID(conversationID))")
        } catch {
            GMLog.debug(.network, "Typing start failed conv=\(shortID(conversationID)) err=\(error.localizedDescription)")
        }
    }

    func syncAllMessagesForSelected() async {
        guard let client, let conversationID = selectedConversationID else { return }
        guard !isSyncingAllMessages else { return }

        isSyncingAllMessages = true
        syncProgressText = "Syncing..."
        GMLog.info(.app, "Sync all conv=\(shortID(conversationID))")
        defer {
            isSyncingAllMessages = false
            syncProgressText = ""
            GMLog.info(.app, "Sync all finished conv=\(shortID(conversationID)) count=\(messages.count)")
        }

        var cursor: Client_Cursor? = nil
        var all: [Conversations_Message] = []
        var seen = Set<String>()

        while true {
            do {
                let response = try await client.fetchMessagesPage(
                    conversationID: conversationID,
                    count: 200,
                    cursor: cursor
                )

                let page = response.messages.filter { seen.insert($0.messageID).inserted }
                if page.isEmpty {
                    break
                }

                all.append(contentsOf: page)
                all.sort(by: { $0.timestamp < $1.timestamp })

                messages = all
                syncProgressText = "Fetched \(messages.count) messages..."

                cursor = response.hasCursor ? response.cursor : nil
                if cursor == nil {
                    break
                }
            } catch {
                errorMessage = "Sync failed: \(error.localizedDescription)"
                break
            }
        }

        // Keep in-memory pagination state consistent with what we persisted.
        messagesCursor = cursor
        await cache.saveMessages(conversationID: conversationID, messages: messages, cursor: cursor)
    }

    func sendMessage(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let client, let conversationID = selectedConversationID else { return }

        let tmpID = generateTmpID()
        let ts = Int64(Date().timeIntervalSince1970 * 1_000_000) // microseconds

        do {
            let conv = try await resolveConversationForSending(conversationID: conversationID, client: client)

            // Optimistically show the outgoing message immediately.
            let placeholder = makeOutgoingPlaceholderMessage(
                conversation: conv,
                tmpID: tmpID,
                timestamp: ts,
                text: trimmed,
                mediaContent: nil
            )
            upsertSelectedConversationMessage(placeholder)
            _ = upsertConversationFromMessage(placeholder, markUnread: false)
            await cache.saveMessages(conversationID: conversationID, messages: messages, cursor: messagesCursor)

            await stopOutgoingTypingIfNeeded()

            var info = Conversations_MessageInfo()
            var msgContent = Conversations_MessageContent()
            msgContent.content = trimmed
            info.messageContent = msgContent

            let req = buildSendMessageRequest(
                conversation: conv,
                tmpID: tmpID,
                messageInfo: [info]
            )

            let resp = try await client.sendMessage(req)
            GMLog.info(.network, "Send message conv=\(shortID(conversationID)) tmpID=\(shortID(tmpID)) status=\(resp.status.rawValue)")

            guard resp.status == .success else {
                throw NSError(
                    domain: "SwiftGMessages",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Send failed (status=\(resp.status.rawValue))"]
                )
            }

            // Server accepted the message; keep it until the remote echo replaces it.
            updateLocalOutgoingMessage(tmpID: tmpID, status: .outgoingComplete, errorText: nil)
            await cache.saveMessages(conversationID: conversationID, messages: messages, cursor: messagesCursor)
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            GMLog.error(.network, "Failed to send message conv=\(shortID(conversationID)) tmpID=\(shortID(tmpID)): \(error.localizedDescription)")
            updateLocalOutgoingMessage(tmpID: tmpID, status: .outgoingFailedGeneric, errorText: error.localizedDescription)
            await cache.saveMessages(conversationID: conversationID, messages: messages, cursor: messagesCursor)
        }
    }

    func sendMedia(fileURL: URL, caption: String? = nil) async {
        guard let client, let conversationID = selectedConversationID else { return }
        GMLog.info(.media, "Send media conv=\(shortID(conversationID)) file=\(fileURL.lastPathComponent)")

        // Read the file off the main actor to avoid UI stalls.
        let (data, fileName, mimeType): (Data, String, String)
        do {
            (data, fileName, mimeType) = try await Task.detached(priority: .userInitiated) {
                let data = try Data(contentsOf: fileURL)
                let fileName = fileURL.lastPathComponent
                let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                return (data, fileName, mimeType)
            }.value
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
            return
        }

        let tmpID = generateTmpID()
        let ts = Int64(Date().timeIntervalSince1970 * 1_000_000) // microseconds

        do {
            let conv = try await resolveConversationForSending(conversationID: conversationID, client: client)

            await stopOutgoingTypingIfNeeded()

            let media = try await client.uploadMedia(data: data, fileName: fileName, mimeType: mimeType)
            GMLog.info(.media, "Uploaded media conv=\(shortID(conversationID)) tmpID=\(shortID(tmpID)) file=\(fileName) bytes=\(data.count) mime=\(mimeType) mediaID=\(shortID(media.mediaID))")

            // Optimistically show the outgoing attachment.
            let placeholder = makeOutgoingPlaceholderMessage(
                conversation: conv,
                tmpID: tmpID,
                timestamp: ts,
                text: caption,
                mediaContent: media
            )
            upsertSelectedConversationMessage(placeholder)
            _ = upsertConversationFromMessage(placeholder, markUnread: false)
            await cache.saveMessages(conversationID: conversationID, messages: messages, cursor: messagesCursor)

            var infos: [Conversations_MessageInfo] = []
            var mediaInfo = Conversations_MessageInfo()
            mediaInfo.mediaContent = media
            infos.append(mediaInfo)

            if let caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var textInfo = Conversations_MessageInfo()
                var msgContent = Conversations_MessageContent()
                msgContent.content = caption
                textInfo.messageContent = msgContent
                infos.append(textInfo)
            }

            let req = buildSendMessageRequest(
                conversation: conv,
                tmpID: tmpID,
                messageInfo: infos
            )

            let resp = try await client.sendMessage(req)
            GMLog.info(.media, "Send media conv=\(shortID(conversationID)) tmpID=\(shortID(tmpID)) status=\(resp.status.rawValue)")

            guard resp.status == .success else {
                throw NSError(
                    domain: "SwiftGMessages",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Send failed (status=\(resp.status.rawValue))"]
                )
            }

            updateLocalOutgoingMessage(tmpID: tmpID, status: .outgoingComplete, errorText: nil)
            await cache.saveMessages(conversationID: conversationID, messages: messages, cursor: messagesCursor)
        } catch {
            errorMessage = "Failed to send media: \(error.localizedDescription)"
            GMLog.error(.media, "Failed to send media conv=\(shortID(conversationID)) tmpID=\(shortID(tmpID)) file=\(fileName): \(error.localizedDescription)")
            updateLocalOutgoingMessage(tmpID: tmpID, status: .outgoingFailedGeneric, errorText: error.localizedDescription)
            await cache.saveMessages(conversationID: conversationID, messages: messages, cursor: messagesCursor)
        }
    }

    private func generateTmpID() -> String {
        let n = Int64.random(in: 0..<1_000_000_000_000)
        return String(format: "tmp_%012lld", n)
    }

    private func resolveConversationForSending(
        conversationID: String,
        client: GMClient
    ) async throws -> Conversations_Conversation {
        if let conv = conversations.first(where: { $0.conversationID == conversationID }),
           !conv.defaultOutgoingID.isEmpty
        {
            return conv
        }

        GMLog.debug(.network, "Fetching conversation metadata for send conv=\(shortID(conversationID))")
        let conv = try await client.getConversation(id: conversationID)

        if let idx = conversations.firstIndex(where: { $0.conversationID == conversationID }) {
            conversations[idx] = conv
        } else {
            conversations.append(conv)
        }
        conversations.sort(by: { $0.lastMessageTimestamp > $1.lastMessageTimestamp })
        await cache.saveConversations(conversations)

        guard !conv.defaultOutgoingID.isEmpty else {
            throw NSError(
                domain: "SwiftGMessages",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Conversation metadata missing outgoing participant id. Try refreshing conversations."]
            )
        }
        return conv
    }

    private func buildSendMessageRequest(
        conversation: Conversations_Conversation,
        tmpID: String,
        messageInfo: [Conversations_MessageInfo]
    ) -> Client_SendMessageRequest {
        var req = Client_SendMessageRequest()
        req.conversationID = conversation.conversationID
        req.tmpID = tmpID

        let simPayload: Settings_SIMPayload? = {
            if conversation.hasSimCard, conversation.simCard.hasSimdata, conversation.simCard.simdata.hasSimpayload {
                return conversation.simCard.simdata.simpayload
            }
            if let me = conversation.participants.first(where: { $0.isMe }), me.hasSimPayload {
                return me.simPayload
            }
            return nil
        }()
        if let simPayload {
            req.simpayload = simPayload
        }

        var payload = Client_MessagePayload()
        payload.tmpID = tmpID
        payload.conversationID = conversation.conversationID
        payload.participantID = conversation.defaultOutgoingID
        payload.tmpID2 = tmpID
        if !messageInfo.isEmpty {
            payload.messageInfo = messageInfo
        }
        req.messagePayload = payload
        return req
    }

    private func makeOutgoingPlaceholderMessage(
        conversation: Conversations_Conversation,
        tmpID: String,
        timestamp: Int64,
        text: String?,
        mediaContent: Conversations_MediaContent?
    ) -> Conversations_Message {
        var msg = Conversations_Message()
        msg.messageID = tmpID
        msg.timestamp = timestamp
        msg.conversationID = conversation.conversationID
        msg.participantID = conversation.defaultOutgoingID
        msg.tmpID = tmpID

        var st = Conversations_MessageStatus()
        st.status = .outgoingSending
        msg.messageStatus = st

        if let me = conversation.participants.first(where: { $0.isMe }) {
            msg.senderParticipant = me
        } else {
            var me = Conversations_Participant()
            me.isMe = true
            msg.senderParticipant = me
        }

        var infos: [Conversations_MessageInfo] = []
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var info = Conversations_MessageInfo()
            var msgContent = Conversations_MessageContent()
            msgContent.content = text
            info.messageContent = msgContent
            infos.append(info)
        }
        if let mediaContent {
            var info = Conversations_MessageInfo()
            info.mediaContent = mediaContent
            infos.append(info)
        }
        msg.messageInfo = infos
        return msg
    }

    private func updateLocalOutgoingMessage(
        tmpID: String,
        status: Conversations_MessageStatusType,
        errorText: String?
    ) {
        guard let idx = messages.firstIndex(where: { $0.tmpID == tmpID || $0.messageID == tmpID }) else { return }
        var msg = messages[idx]
        var st = msg.messageStatus
        st.status = status
        if let errorText, !errorText.isEmpty {
            st.errMsg = errorText
            st.statusText = errorText
        }
        msg.messageStatus = st
        messages[idx] = msg

        _ = upsertConversationFromMessage(msg, markUnread: false)
    }

    private func mergeMessages(
        existing: [Conversations_Message],
        incoming: [Conversations_Message]
    ) -> [Conversations_Message] {
        guard !incoming.isEmpty else { return existing }

        var out = existing
        var idIndex: [String: Int] = [:]
        var tmpIndex: [String: Int] = [:]
        idIndex.reserveCapacity(out.count)
        tmpIndex.reserveCapacity(out.count)

        for (idx, msg) in out.enumerated() {
            if !msg.messageID.isEmpty { idIndex[msg.messageID] = idx }
            if !msg.tmpID.isEmpty { tmpIndex[msg.tmpID] = idx }
        }

        func replace(at index: Int, with msg: Conversations_Message) {
            let old = out[index]
            if !old.messageID.isEmpty, idIndex[old.messageID] == index {
                idIndex.removeValue(forKey: old.messageID)
            }
            if !old.tmpID.isEmpty, tmpIndex[old.tmpID] == index {
                tmpIndex.removeValue(forKey: old.tmpID)
            }

            out[index] = msg
            if !msg.messageID.isEmpty { idIndex[msg.messageID] = index }
            if !msg.tmpID.isEmpty { tmpIndex[msg.tmpID] = index }
        }

        for msg in incoming {
            if !msg.messageID.isEmpty, let idx = idIndex[msg.messageID] {
                replace(at: idx, with: msg)
                continue
            }
            if !msg.tmpID.isEmpty, let idx = tmpIndex[msg.tmpID] {
                replace(at: idx, with: msg)
                continue
            }
            out.append(msg)
            let idx = out.count - 1
            if !msg.messageID.isEmpty { idIndex[msg.messageID] = idx }
            if !msg.tmpID.isEmpty { tmpIndex[msg.tmpID] = idx }
        }

        return out
    }

    func createConversation(phoneNumberRaw: String, initialMessage: String? = nil) async {
        guard let client else { return }
        let normalized = normalizePhoneNumber(phoneNumberRaw)
        guard !normalized.isEmpty else { return }

        do {
            await stopOutgoingTypingIfNeeded()
            let resp = try await client.getOrCreateConversation(numbers: [normalized])
            let conv = resp.conversation
            GMLog.info(.network, "Created/loaded conversation conv=\(shortID(conv.conversationID))")

            // Refresh list so the conversation appears with correct ordering/metadata.
            await refreshConversations()
            selectedConversationID = conv.conversationID
            UserDefaults.standard.set(conv.conversationID, forKey: Self.lastSelectedConversationKey)
            await loadMessagesForSelected(reset: true, forceNetwork: true)

            if let initialMessage, !initialMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await sendMessage(text: initialMessage)
            }
        } catch {
            errorMessage = "Failed to create conversation: \(error.localizedDescription)"
            GMLog.error(.network, "Failed to create conversation: \(error.localizedDescription)")
        }
    }

    /// Ensure the attachment bytes exist on disk and return a local file URL.
    ///
    /// Prefer using `preferThumbnail=true` for inline display to avoid pulling full-res media eagerly.
    func ensureAttachmentFileURL(
        _ media: Conversations_MediaContent,
        preferThumbnail: Bool
    ) async throws -> URL {
        guard let client else {
            throw NSError(domain: "SwiftGMessages", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }

        // Media can arrive in multiple shapes:
        // - Full attachment: mediaID + decryptionKey
        // - Thumbnail only: thumbnailMediaID + thumbnailDecryptionKey
        // - Inline media: mediaData is already embedded (no download step)
        let fullID = media.mediaID
        let thumbID = media.thumbnailMediaID
        let fullKey = media.decryptionKey
        let thumbKey = media.thumbnailDecryptionKey
        let inlineBytes = media.mediaData

        var mimeType = media.mimeType
        if mimeType.isEmpty {
            let ext = MediaTypes.extensionFor(format: media.format)
            mimeType = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        }

        // Inline is always best if present (no network).
        if !inlineBytes.isEmpty {
            let digest = await Task.detached(priority: .userInitiated) {
                let d = SHA256.hash(data: inlineBytes)
                return d.map { String(format: "%02x", $0) }.joined()
            }.value
            let cacheKey = "inline:\(digest)"

            if let cached = await cache.cachedMediaURL(mediaID: cacheKey) {
                return cached
            }

            let url = await cache.storeMedia(
                data: inlineBytes,
                mediaID: cacheKey,
                mimeType: mimeType,
                suggestedName: media.mediaName.isEmpty ? nil : media.mediaName
            ) ?? makeTempMediaURL(mimeType: mimeType)

            if !FileManager.default.fileExists(atPath: url.path) {
                try inlineBytes.write(to: url, options: .atomic)
            }
            return url
        }

        enum RemoteChoice {
            case full
            case thumbnail

            var label: String { self == .full ? "full" : "thumb" }
        }

        let order: [RemoteChoice] = preferThumbnail ? [.thumbnail, .full] : [.full, .thumbnail]
        for choice in order {
            switch choice {
            case .full:
                if !fullID.isEmpty, !fullKey.isEmpty {
                    if let cached = await cache.cachedMediaURL(mediaID: fullID) {
                        return cached
                    }
                    GMLog.info(.media, "Downloading media kind=full id=\(shortID(fullID)) mime=\(mimeType) keyLen=\(fullKey.count)")
                    let data = try await client.downloadMedia(mediaID: fullID, decryptionKey: fullKey)
                    GMLog.info(.media, "Downloaded media kind=full id=\(shortID(fullID)) bytes=\(data.count)")

                    let url = await cache.storeMedia(
                        data: data,
                        mediaID: fullID,
                        mimeType: mimeType,
                        suggestedName: media.mediaName.isEmpty ? nil : media.mediaName
                    ) ?? makeTempMediaURL(mimeType: mimeType)

                    if !FileManager.default.fileExists(atPath: url.path) {
                        try data.write(to: url, options: .atomic)
                    }
                    return url
                }
            case .thumbnail:
                if !thumbID.isEmpty, !thumbKey.isEmpty {
                    if let cached = await cache.cachedMediaURL(mediaID: thumbID) {
                        return cached
                    }
                    GMLog.info(.media, "Downloading media kind=thumb id=\(shortID(thumbID)) mime=\(mimeType) keyLen=\(thumbKey.count)")
                    let data = try await client.downloadMedia(mediaID: thumbID, decryptionKey: thumbKey)
                    GMLog.info(.media, "Downloaded media kind=thumb id=\(shortID(thumbID)) bytes=\(data.count)")

                    let url = await cache.storeMedia(
                        data: data,
                        mediaID: thumbID,
                        mimeType: mimeType,
                        suggestedName: media.mediaName.isEmpty ? nil : media.mediaName
                    ) ?? makeTempMediaURL(mimeType: mimeType)

                    if !FileManager.default.fileExists(atPath: url.path) {
                        try data.write(to: url, options: .atomic)
                    }
                    return url
                }
            }
        }

        throw NSError(
            domain: "SwiftGMessages",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Attachment isn't available to download yet. Open Google Messages on your phone and download it there first, then try again."]
        )
    }

    func downloadAndOpenMedia(_ media: Conversations_MediaContent) async {
        do {
            let url = try await ensureAttachmentFileURL(media, preferThumbnail: false)
            #if os(macOS)
            let ok = NSWorkspace.shared.open(url)
            if !ok {
                GMLog.warn(.media, "NSWorkspace.open failed url=\(url.lastPathComponent)")
            }
            #endif
        } catch {
            errorMessage = "Failed to download media: \(error.localizedDescription)"
            GMLog.error(.media, "Failed to download media: \(error.localizedDescription)")
        }
    }

    func deleteMessage(messageID: String) async {
        guard let client else { return }
        do {
            let ok = try await client.deleteMessage(messageID: messageID)
            if ok {
                messages.removeAll { $0.messageID == messageID }
                scheduleConversationsRefresh()
                GMLog.info(.network, "Deleted message id=\(shortID(messageID))")
            }
        } catch {
            errorMessage = "Failed to delete message: \(error.localizedDescription)"
            GMLog.error(.network, "Failed to delete message id=\(shortID(messageID)): \(error.localizedDescription)")
        }
    }

    func react(to messageID: String, emoji: String) async {
        guard let client else { return }
        do {
            try await client.sendReaction(messageID: messageID, emoji: emoji, action: .add)
            GMLog.info(.network, "React message id=\(shortID(messageID)) emoji=\(emoji)")
        } catch {
            errorMessage = "Failed to send reaction: \(error.localizedDescription)"
            GMLog.error(.network, "Failed to react message id=\(shortID(messageID)): \(error.localizedDescription)")
        }
    }

    func setConversationArchived(conversationID: String, archived: Bool) async {
        guard let client else { return }
        do {
            try await client.updateConversationStatus(
                conversationID: conversationID,
                status: archived ? .archived : .active
            )
            GMLog.info(.network, "Set archived conv=\(shortID(conversationID)) archived=\(archived)")
            await refreshConversations()
        } catch {
            errorMessage = "Failed to update conversation: \(error.localizedDescription)"
            GMLog.error(.network, "Failed to archive conv=\(shortID(conversationID)): \(error.localizedDescription)")
        }
    }

    func setConversationMuted(conversationID: String, muted: Bool) async {
        guard let client else { return }
        do {
            try await client.setConversationMuted(conversationID: conversationID, isMuted: muted)
            GMLog.info(.network, "Set muted conv=\(shortID(conversationID)) muted=\(muted)")
            await refreshConversations()
        } catch {
            errorMessage = "Failed to update conversation: \(error.localizedDescription)"
            GMLog.error(.network, "Failed to mute conv=\(shortID(conversationID)): \(error.localizedDescription)")
        }
    }

    func copySelectedConversationContext(limit: Int = 500) {
        guard let conversationID = selectedConversationID else { return }
        let title: String = conversations.first(where: { $0.conversationID == conversationID }).map {
            $0.name.isEmpty ? $0.conversationID : $0.name
        } ?? conversationID

        let slice = messages.suffix(max(1, limit))
        var lines: [String] = []
        lines.append("# \(title)")
        lines.append("")

        for msg in slice {
            let ts = gmDate(from: msg.timestamp).formatted(date: .numeric, time: .standard)
            let sender = msg.participantID.isEmpty ? "unknown" : msg.participantID

            var parts: [String] = []
            for info in msg.messageInfo {
                switch info.data {
                case .messageContent(let c):
                    if !c.content.isEmpty { parts.append(c.content) }
                case .mediaContent(let m):
                    let name = m.mediaName.isEmpty ? "attachment" : m.mediaName
                    let mime = m.mimeType.isEmpty ? "" : " (\(m.mimeType))"
                    parts.append("[\(name)\(mime)]")
                case .none:
                    break
                }
            }

            let body = parts.isEmpty ? "(empty)" : parts.joined(separator: " ")
            lines.append("[\(ts)] \(sender): \(body)")
        }

        let out = lines.joined(separator: "\n")

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
        #endif
    }

    // MARK: - Private

    private func connectAndBootstrap() async throws {
        guard let client else { return }
        connectionStatusText = "Connecting..."
        GMLog.info(.app, "Connecting (long poll)")
        try await client.connect()
        connectionStatusText = "Connected"
        GMLog.info(.app, "Connected")

        await refreshConversations()
    }

    private func scheduleConversationsRefresh() {
        refreshConversationsTask?.cancel()
        refreshConversationsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            await self?.refreshConversations()
        }
    }

    private func scheduleReconnect(reason: String, delaySeconds: TimeInterval) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            self.connectionStatusText = reason
            GMLog.warn(.app, "Reconnect scheduled reason=\(reason) delay=\(delaySeconds)s")
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))

            guard let client = self.client else { return }
            do {
                try await client.reconnect()
                self.connectionStatusText = "Connected"
                GMLog.info(.app, "Reconnected")
                await self.refreshConversations()
            } catch {
                self.connectionStatusText = "Disconnected"
                self.errorMessage = "Reconnect failed: \(error.localizedDescription)"
                GMLog.error(.app, "Reconnect failed: \(error.localizedDescription)")
            }
        }
    }

    private func handle(_ event: GMEvent) async {
        switch event {
        case .qrCode(let url):
            pairingQRCodeURL = url
            if screen == .needsPairing {
                screen = .pairing
            }
            GMLog.info(.events, "Event qrCode urlLen=\(url.count)")

        case .pairSuccessful(let phoneID, _):
            pairingStatusText = "Paired (\(phoneID)). Saving..."
            GMLog.info(.events, "Event pairSuccessful phoneID=\(phoneID)")
            do {
                try await client?.saveAuthData(to: store)
            } catch {
                errorMessage = "Paired, but failed to save auth: \(error.localizedDescription)"
                GMLog.error(.events, "Failed to save auth: \(error.localizedDescription)")
                return
            }

            pairingStatusText = "Finalizing pairing..."
            // Give the phone time to persist the pair data, then reconnect as a normal session.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            do {
                try await client?.reconnect()
                screen = .ready
                connectionStatusText = "Connected"
                GMLog.info(.events, "Reconnect after pairing succeeded")
                await refreshConversations()
            } catch {
                screen = .ready
                connectionStatusText = "Disconnected"
                errorMessage = "Paired, but reconnect failed: \(error.localizedDescription)"
                GMLog.error(.events, "Reconnect after pairing failed: \(error.localizedDescription)")
            }

        case .gaiaPairingEmoji:
            // Not currently surfaced in the UI.
            break

        case .message(let msg, let isOld):
            GMLog.debug(.events, "Event message conv=\(shortID(msg.conversationID)) id=\(shortID(msg.messageID)) ts=\(describeTimestamp(msg.timestamp))")
            await cache.upsertMessageIfCached(msg)

            let fromMe = msg.hasSenderParticipant ? msg.senderParticipant.isMe : false

            if msg.conversationID == selectedConversationID {
                upsertSelectedConversationMessage(msg)
                await cache.saveMessages(conversationID: msg.conversationID, messages: messages, cursor: messagesCursor)
                scheduleMarkReadForSelectedIfNeeded(reason: isOld ? "message_update_old" : "message_event")
                scheduleLinkPreviewPrefetchIfNeeded(messages: [msg])
            }

            let hadConversation = upsertConversationFromMessage(msg, markUnread: (!fromMe && !isOld && msg.conversationID != selectedConversationID))
            if !hadConversation {
                scheduleConversationsRefresh()
            }

            if !isOld {
                await postNotificationIfNeeded(for: msg)
            }

        case .conversation(let conv):
            if let idx = conversations.firstIndex(where: { $0.conversationID == conv.conversationID }) {
                conversations[idx] = conv
            } else {
                conversations.append(conv)
            }
            conversations.sort(by: { $0.lastMessageTimestamp > $1.lastMessageTimestamp })
            await cache.saveConversations(conversations)
            GMLog.debug(.events, "Event conversation id=\(shortID(conv.conversationID)) lastTs=\(describeTimestamp(conv.lastMessageTimestamp))")

        case .typing(let data):
            handleTypingEvent(data)

        case .listenTemporaryError(let error):
            scheduleReconnect(reason: "Reconnecting...", delaySeconds: 2)
            self.errorMessage = "Temporary listen error: \(error.localizedDescription)"
            GMLog.warn(.events, "Event listenTemporaryError: \(error.localizedDescription)")

        case .listenFatalError(let error):
            scheduleReconnect(reason: "Reconnecting...", delaySeconds: 2)
            self.errorMessage = "Fatal listen error: \(error.localizedDescription)"
            GMLog.error(.events, "Event listenFatalError: \(error.localizedDescription)")

        case .listenRecovered:
            connectionStatusText = "Connected"
            errorMessage = nil
            GMLog.info(.events, "Event listenRecovered")

        case .pingFailed(let error, let count):
            connectionStatusText = "Ping failed (\(count)x): \(error.localizedDescription)"
            GMLog.warn(.events, "Event pingFailed count=\(count) err=\(error.localizedDescription)")

        case .phoneNotResponding:
            connectionStatusText = "Phone not responding"
            GMLog.warn(.events, "Event phoneNotResponding")

        case .phoneRespondingAgain:
            connectionStatusText = "Connected"
            GMLog.info(.events, "Event phoneRespondingAgain")

        case .noDataReceived:
            break

        case .userAlert:
            break

        case .settings(let settings):
            // Keep latest phone settings (RCS toggles, version, SIM info, etc.) for Settings UI.
            phoneSettings = settings
            GMLog.debug(.events, "Event settings (bugleVersion=\(settings.bugleVersion))")

        case .browserActive:
            break

        case .gaiaLoggedOut:
            errorMessage = "Logged out"
            GMLog.warn(.events, "Event gaiaLoggedOut")

        case .accountChange:
            break

        case .requestError(let info):
            errorMessage = "Request error (\(info.action))"
            GMLog.error(.events, "Event requestError action=\(info.action)")

        case .httpError(let info):
            errorMessage = "HTTP error (\(info.statusCode)) (\(info.action))"
            GMLog.error(.events, "Event httpError action=\(info.action) status=\(info.statusCode)")

        case .authTokenRefreshed:
            break
        }
    }

    private func stopOutgoingTypingIfNeeded() async {
        outgoingTypingStopTask?.cancel()
        outgoingTypingStopTask = nil

        guard outgoingTypingIsActive else { return }

        guard UserDefaults.standard.bool(forKey: GMPreferences.sendTypingIndicators) else {
            outgoingTypingIsActive = false
            outgoingTypingConversationID = nil
            return
        }

        guard let client else {
            outgoingTypingIsActive = false
            outgoingTypingConversationID = nil
            return
        }

        let conversationID = outgoingTypingConversationID ?? selectedConversationID
        guard let conversationID, !conversationID.isEmpty else {
            outgoingTypingIsActive = false
            outgoingTypingConversationID = nil
            return
        }

        do {
            try await client.setTyping(conversationID: conversationID, isTyping: false)
            GMLog.debug(.network, "Typing stop conv=\(shortID(conversationID))")
        } catch {
            GMLog.debug(.network, "Typing stop failed conv=\(shortID(conversationID)) err=\(error.localizedDescription)")
        }

        outgoingTypingIsActive = false
        outgoingTypingConversationID = nil
    }

    private func scheduleMarkReadForSelectedIfNeeded(reason: String) {
        guard UserDefaults.standard.bool(forKey: GMPreferences.sendReadReceipts) else { return }
        guard let client, let conversationID = selectedConversationID else { return }

        #if os(macOS)
        if !NSApp.isActive {
            GMLog.debug(.network, "Skip markRead (inactive) conv=\(shortID(conversationID)) reason=\(reason)")
            return
        }
        #endif

        let candidate = messages.last(where: { msg in
            if msg.hasSenderParticipant {
                return !msg.senderParticipant.isMe
            }
            return true
        }) ?? messages.last

        guard let candidate else { return }
        guard !candidate.messageID.isEmpty else { return }

        if lastMarkedReadByConversation[conversationID] == candidate.messageID {
            return
        }

        markReadTask?.cancel()
        markReadTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }

            guard let stillSelected = self.selectedConversationID, stillSelected == conversationID else { return }

            let msgToMark = self.messages.last(where: { m in
                if m.hasSenderParticipant { return !m.senderParticipant.isMe }
                return true
            }) ?? self.messages.last
            guard let msgToMark else { return }
            guard !msgToMark.messageID.isEmpty else { return }

            if self.lastMarkedReadByConversation[conversationID] == msgToMark.messageID { return }

            do {
                try await client.markRead(conversationID: conversationID, messageID: msgToMark.messageID)
                self.lastMarkedReadByConversation[conversationID] = msgToMark.messageID
                GMLog.info(.network, "Mark read conv=\(shortID(conversationID)) msg=\(shortID(msgToMark.messageID)) reason=\(reason)")

                if let idx = self.conversations.firstIndex(where: { $0.conversationID == conversationID }) {
                    self.conversations[idx].unread = false
                    await self.cache.saveConversations(self.conversations)
                }
            } catch {
                GMLog.debug(.network, "Mark read failed conv=\(shortID(conversationID)) msg=\(shortID(msgToMark.messageID)) err=\(error.localizedDescription)")
            }
        }
    }

    private func upsertSelectedConversationMessage(_ msg: Conversations_Message) {
        guard msg.conversationID == selectedConversationID else { return }

        if let idx = messages.firstIndex(where: { $0.messageID == msg.messageID }) {
            messages[idx] = msg
        } else if !msg.tmpID.isEmpty, let idx = messages.firstIndex(where: { !$0.tmpID.isEmpty && $0.tmpID == msg.tmpID }) {
            messages[idx] = msg
        } else {
            messages.append(msg)
        }
        messages.sort(by: { $0.timestamp < $1.timestamp })
    }

    @discardableResult
    private func upsertConversationFromMessage(_ msg: Conversations_Message, markUnread: Bool) -> Bool {
        guard !msg.conversationID.isEmpty else { return false }

        let fromMe = msg.hasSenderParticipant ? msg.senderParticipant.isMe : false

        let displayContent: String = {
            for info in msg.messageInfo {
                if case .messageContent(let c)? = info.data, !c.content.isEmpty {
                    return c.content
                }
            }
            for info in msg.messageInfo {
                if case .mediaContent(let m)? = info.data {
                    if !m.mediaName.isEmpty { return m.mediaName }
                    return "Attachment"
                }
            }
            return "(message)"
        }()

        let displayName: String = {
            guard msg.hasSenderParticipant else { return "" }
            let p = msg.senderParticipant
            if !p.firstName.isEmpty { return p.firstName }
            if !p.fullName.isEmpty { return p.fullName }
            if !p.formattedNumber.isEmpty { return p.formattedNumber }
            if !p.id.number.isEmpty { return p.id.number }
            return ""
        }()

        guard let idx = conversations.firstIndex(where: { $0.conversationID == msg.conversationID }) else {
            return false
        }

        var conv = conversations[idx]
        let wasLatestByID = !conv.latestMessageID.isEmpty && conv.latestMessageID == msg.messageID
        let isNewerOrSame = msg.timestamp >= conv.lastMessageTimestamp

        // Always keep the best-known last timestamp, but don't clobber the conversation preview
        // when the event is an update for an older message (delivery/read receipts, media upgrade, etc.).
        conv.lastMessageTimestamp = max(conv.lastMessageTimestamp, msg.timestamp)

        if isNewerOrSame || wasLatestByID || conv.latestMessageID.isEmpty {
            conv.latestMessage.displayContent = displayContent
            conv.latestMessage.fromMe = fromMe ? 1 : 0
            if !displayName.isEmpty {
                conv.latestMessage.displayName = displayName
            }
            conv.latestMessage.latestMessageStatus.status = msg.messageStatus.status
            conv.latestMessageID = msg.messageID
        }

        if markUnread {
            conv.unread = true
        }

        conversations[idx] = conv
        conversations.sort(by: { $0.lastMessageTimestamp > $1.lastMessageTimestamp })
        Task { [conversations, cache] in
            await cache.saveConversations(conversations)
        }
        return true
    }

    private func postNotificationIfNeeded(for msg: Conversations_Message) async {
        guard UserDefaults.standard.bool(forKey: GMPreferences.notificationsEnabled) else { return }

        let fromMe = msg.hasSenderParticipant ? msg.senderParticipant.isMe : false
        guard !fromMe else { return }

        #if os(macOS)
        if NSApp.isActive && !UserDefaults.standard.bool(forKey: GMPreferences.notificationsWhenActive) {
            return
        }
        #endif

        let id = msg.messageID
        guard !id.isEmpty else { return }
        if notifiedMessageIDs.contains(id) { return }
        notifiedMessageIDs.insert(id)
        if notifiedMessageIDs.count > 1024 {
            notifiedMessageIDs = Set(notifiedMessageIDs.suffix(512))
        }

        let authorized = await GMNotifications.requestAuthorizationIfNeeded()
        guard authorized else { return }

        let previewEnabled = UserDefaults.standard.bool(forKey: GMPreferences.notificationsPreview)
        let playSound = UserDefaults.standard.bool(forKey: GMPreferences.notificationsSound)

        let title: String = conversations.first(where: { $0.conversationID == msg.conversationID }).map {
            $0.name.isEmpty ? $0.conversationID : $0.name
        } ?? "Message"

        let body: String = {
            guard previewEnabled else { return "New message" }
            for info in msg.messageInfo {
                if case .messageContent(let c)? = info.data, !c.content.isEmpty {
                    return c.content
                }
            }
            for info in msg.messageInfo {
                if case .mediaContent(let m)? = info.data {
                    if !m.mediaName.isEmpty { return m.mediaName }
                    return "Attachment"
                }
            }
            return "New message"
        }()

        await GMNotifications.postMessageNotification(
            identifier: id,
            threadIdentifier: msg.conversationID,
            title: title,
            subtitle: nil,
            body: body,
            playSound: playSound
        )
    }

    private func handleTypingEvent(_ data: Events_TypingData) {
        guard UserDefaults.standard.bool(forKey: GMPreferences.showTypingIndicators) else { return }
        guard !data.conversationID.isEmpty else { return }
        guard data.conversationID == selectedConversationID else { return }

        remoteTypingClearTask?.cancel()
        remoteTypingClearTask = nil

        let isStarted: Bool
        switch data.type {
        case .startedTyping:
            isStarted = true
        default:
            isStarted = false
        }

        if !isStarted {
            typingIndicatorText = nil
            return
        }

        let name = typingUserDisplayName(
            number: data.hasUser ? data.user.number : "",
            conversationID: data.conversationID
        )
        if let name, !name.isEmpty {
            typingIndicatorText = "\(name) is typing..."
        } else {
            typingIndicatorText = "Typing..."
        }

        remoteTypingClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            self?.typingIndicatorText = nil
        }
    }

    private func typingUserDisplayName(number: String, conversationID: String) -> String? {
        let normalized = normalizePhoneNumber(number)
        guard let conv = conversations.first(where: { $0.conversationID == conversationID }) else { return nil }

        let candidates = conv.participants.filter { !$0.isMe }
        if let p = candidates.first(where: { $0.id.number == number || $0.formattedNumber == number }) {
            return participantName(p)
        }
        if !normalized.isEmpty {
            if let p = candidates.first(where: {
                normalizePhoneNumber($0.id.number) == normalized ||
                normalizePhoneNumber($0.formattedNumber) == normalized
            }) {
                return participantName(p)
            }
        }
        return nil
    }

    private func participantName(_ p: Conversations_Participant) -> String? {
        if !p.firstName.isEmpty { return p.firstName }
        if !p.fullName.isEmpty { return p.fullName }
        if !p.formattedNumber.isEmpty { return p.formattedNumber }
        if !p.id.number.isEmpty { return p.id.number }
        return nil
    }

    func linkMetadata(for url: URL) async -> LPLinkMetadata? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }

        let key = url.absoluteString
        if let cached = linkMetadataMemory[key] {
            return cached
        }
        if let task = linkMetadataTasks[key] {
            return await task.value
        }

        let task = Task<LPLinkMetadata?, Never> { [weak self] in
            guard let self else { return nil }

            if let data = await self.cache.loadLinkMetadataData(urlString: key),
               let metadata = try? NSKeyedUnarchiver.unarchivedObject(ofClass: LPLinkMetadata.self, from: data)
            {
                return metadata
            }

            let metadata = await self.fetchLinkMetadataFromNetwork(url)
            if let metadata,
               let data = try? NSKeyedArchiver.archivedData(withRootObject: metadata, requiringSecureCoding: true)
            {
                await self.cache.saveLinkMetadataData(urlString: key, data: data)
            }
            return metadata
        }

        linkMetadataTasks[key] = task
        let metadata = await task.value
        linkMetadataTasks[key] = nil

        if let metadata {
            linkMetadataMemory[key] = metadata
        }
        return metadata
    }

    private func scheduleLinkPreviewPrefetchIfNeeded(messages: [Conversations_Message]) {
        guard UserDefaults.standard.bool(forKey: GMPreferences.linkPreviewsEnabled) else { return }
        guard UserDefaults.standard.bool(forKey: GMPreferences.autoLoadLinkPreviews) else { return }

        // Prefetch a small number of recent unique URLs to make previews feel instant.
        let recent = messages.suffix(25)
        var urls: [URL] = []
        urls.reserveCapacity(8)

        var seen = Set<String>()
        for msg in recent.reversed() {
            guard let text = messageText(for: msg), !text.isEmpty else { continue }
            for u in extractURLs(from: text) {
                let key = u.absoluteString
                if seen.insert(key).inserted {
                    urls.append(u)
                    if urls.count >= 8 { break }
                }
            }
            if urls.count >= 8 { break }
        }

        guard !urls.isEmpty else { return }

        linkPrefetchTask?.cancel()
        linkPrefetchTask = Task { [weak self] in
            guard let self else { return }
            for url in urls {
                guard !Task.isCancelled else { break }
                _ = await self.linkMetadata(for: url)
                // Space out fetches a bit to avoid bursts.
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    private func fetchLinkMetadataFromNetwork(_ url: URL) async -> LPLinkMetadata? {
        let provider = LPMetadataProvider()
        provider.shouldFetchSubresources = true
        provider.timeout = 15

        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { cont in
                provider.startFetchingMetadata(for: url) { metadata, error in
                    if let error {
                        GMLog.debug(.network, "Link preview fetch failed host=\(url.host ?? "?") err=\(error.localizedDescription)")
                    }
                    cont.resume(returning: metadata)
                }
            }
        }, onCancel: {
            provider.cancel()
        })
    }

    private func messageText(for msg: Conversations_Message) -> String? {
        for info in msg.messageInfo {
            if case .messageContent(let content)? = info.data {
                if !content.content.isEmpty { return content.content }
            }
        }
        return nil
    }

    private static let urlDetector: NSDataDetector? = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    private func extractURLs(from text: String) -> [URL] {
        guard let detector = Self.urlDetector else { return [] }
        let ns = text as NSString
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        return matches.compactMap(\.url).filter { url in
            let scheme = url.scheme?.lowercased()
            return scheme == "http" || scheme == "https"
        }
    }
}

private func shortID(_ s: String) -> String {
    if s.isEmpty { return "?" }
    return String(s.suffix(6))
}

private func makeTempMediaURL(mimeType: String) -> URL {
    let ext = UTType(mimeType: mimeType)?.preferredFilenameExtension
    let safeExt = (ext?.isEmpty == false) ? ext! : "bin"
    return FileManager.default.temporaryDirectory
        .appendingPathComponent("gm-\(UUID().uuidString)")
        .appendingPathExtension(safeExt)
}

private func describeTimestamp(_ ts: Int64) -> String {
    let absTS = ts >= 0 ? ts : -ts
    let unit: String
    if absTS >= 1_000_000_000_000_000_000 {
        unit = "ns"
    } else if absTS >= 1_000_000_000_000_000 {
        unit = "us"
    } else if absTS >= 1_000_000_000_000 {
        unit = "ms"
    } else {
        unit = "s"
    }
    let d = gmDate(from: ts).formatted(date: .numeric, time: .standard)
    return "\(ts) (\(unit)) -> \(d)"
}

private func normalizePhoneNumber(_ s: String) -> String {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    // Keep a leading "+" if present, and strip other non-digit characters.
    let hasPlus = trimmed.first == "+"
    let digits = trimmed.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
    let digitString = String(String.UnicodeScalarView(digits))

    if hasPlus {
        return "+" + digitString
    }

    // Heuristic for US numbers in local format.
    if digitString.count == 10 {
        return "+1" + digitString
    }
    if digitString.count == 11, digitString.hasPrefix("1") {
        return "+" + digitString
    }

    return digitString
}
