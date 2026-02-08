import Foundation
import Combine
import CryptoKit
import LibGM
import GMProto
import LinkPresentation
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

protocol GMClientProtocol: AnyObject {
    var isConnected: Bool { get async }
    var isLoggedIn: Bool { get async }

    func connect() async throws
    func disconnect() async
    func reconnect() async throws
    func connectBackground() async throws

    func startLogin() async throws -> String
    func saveAuthData(to store: AuthDataStore) async throws
    func unpair() async throws

    func listConversationsPage(
        count: Int,
        folder: Client_ListConversationsRequest.Folder,
        cursor: Client_Cursor?
    ) async throws -> Client_ListConversationsResponse

    func fetchMessages(
        conversationID: String,
        count: Int,
        cursor: Client_Cursor?
    ) async throws -> (messages: [Conversations_Message], cursor: Client_Cursor?)

    func fetchMessagesPage(
        conversationID: String,
        count: Int,
        cursor: Client_Cursor?
    ) async throws -> Client_ListMessagesResponse

    func sendMessage(_ request: Client_SendMessageRequest) async throws -> Client_SendMessageResponse
    func uploadMedia(data: Data, fileName: String, mimeType: String) async throws -> Conversations_MediaContent
    func downloadMedia(mediaID: String, decryptionKey: Data) async throws -> Data

    func deleteMessage(messageID: String) async throws -> Bool
    func sendReaction(
        messageID: String,
        emoji: String,
        action: Client_SendReactionRequest.Action
    ) async throws

    func updateConversationStatus(
        conversationID: String,
        status: Conversations_ConversationStatus
    ) async throws

    func setConversationMuted(conversationID: String, isMuted: Bool) async throws
    func getConversation(id conversationID: String) async throws -> Conversations_Conversation

    func getOrCreateConversation(
        numbers: [String],
        rcsGroupName: String?,
        createRCSGroup: Bool
    ) async throws -> Client_GetOrCreateConversationResponse

    func markRead(conversationID: String, messageID: String) async throws
    func setTyping(conversationID: String, isTyping: Bool) async throws
    func registerPush(keys: PushKeys) async throws
}

actor GMLiveClient: GMClientProtocol {
    private let client: GMClient

    init(client: GMClient) {
        self.client = client
    }

    var isConnected: Bool {
        get async { await client.isConnected }
    }

    var isLoggedIn: Bool {
        get async { await client.isLoggedIn }
    }

    func connect() async throws { try await client.connect() }
    func disconnect() async { await client.disconnect() }
    func reconnect() async throws { try await client.reconnect() }
    func connectBackground() async throws { try await client.connectBackground() }

    func startLogin() async throws -> String {
        try await client.startLogin()
    }

    func saveAuthData(to store: AuthDataStore) async throws {
        try await client.saveAuthData(to: store)
    }

    func unpair() async throws {
        try await client.unpair()
    }

    func listConversationsPage(
        count: Int,
        folder: Client_ListConversationsRequest.Folder,
        cursor: Client_Cursor?
    ) async throws -> Client_ListConversationsResponse {
        try await client.listConversationsPage(count: count, folder: folder, cursor: cursor)
    }

    func fetchMessages(
        conversationID: String,
        count: Int,
        cursor: Client_Cursor?
    ) async throws -> (messages: [Conversations_Message], cursor: Client_Cursor?) {
        try await client.fetchMessages(conversationID: conversationID, count: count, cursor: cursor)
    }

    func fetchMessagesPage(
        conversationID: String,
        count: Int,
        cursor: Client_Cursor?
    ) async throws -> Client_ListMessagesResponse {
        try await client.fetchMessagesPage(conversationID: conversationID, count: count, cursor: cursor)
    }

    func sendMessage(_ request: Client_SendMessageRequest) async throws -> Client_SendMessageResponse {
        try await client.sendMessage(request)
    }

    func uploadMedia(data: Data, fileName: String, mimeType: String) async throws -> Conversations_MediaContent {
        try await client.uploadMedia(data: data, fileName: fileName, mimeType: mimeType)
    }

    func downloadMedia(mediaID: String, decryptionKey: Data) async throws -> Data {
        try await client.downloadMedia(mediaID: mediaID, decryptionKey: decryptionKey)
    }

    func deleteMessage(messageID: String) async throws -> Bool {
        try await client.deleteMessage(messageID: messageID)
    }

    func sendReaction(
        messageID: String,
        emoji: String,
        action: Client_SendReactionRequest.Action
    ) async throws {
        try await client.sendReaction(messageID: messageID, emoji: emoji, action: action)
    }

    func updateConversationStatus(
        conversationID: String,
        status: Conversations_ConversationStatus
    ) async throws {
        try await client.updateConversationStatus(conversationID: conversationID, status: status)
    }

    func setConversationMuted(conversationID: String, isMuted: Bool) async throws {
        try await client.setConversationMuted(conversationID: conversationID, isMuted: isMuted)
    }

    func getConversation(id conversationID: String) async throws -> Conversations_Conversation {
        try await client.getConversation(id: conversationID)
    }

    func getOrCreateConversation(
        numbers: [String],
        rcsGroupName: String?,
        createRCSGroup: Bool
    ) async throws -> Client_GetOrCreateConversationResponse {
        try await client.getOrCreateConversation(
            numbers: numbers,
            rcsGroupName: rcsGroupName,
            createRCSGroup: createRCSGroup
        )
    }

    func markRead(conversationID: String, messageID: String) async throws {
        try await client.markRead(conversationID: conversationID, messageID: messageID)
    }

    func setTyping(conversationID: String, isTyping: Bool) async throws {
        try await client.setTyping(conversationID: conversationID, isTyping: isTyping)
    }

    func registerPush(keys: PushKeys) async throws {
        try await client.registerPush(keys: keys)
    }
}

protocol GMClientFactoryProtocol {
    func loadFromStore(
        _ store: AuthDataStore,
        eventHandler: any GMEventHandler,
        autoReconnectAfterPairing: Bool
    ) async throws -> (any GMClientProtocol)?

    func makeClient(
        eventHandler: any GMEventHandler,
        autoReconnectAfterPairing: Bool
    ) async -> any GMClientProtocol
}

struct GMLiveClientFactory: GMClientFactoryProtocol {
    func loadFromStore(
        _ store: AuthDataStore,
        eventHandler: any GMEventHandler,
        autoReconnectAfterPairing: Bool
    ) async throws -> (any GMClientProtocol)? {
        guard let loaded = try await GMClient.loadFromStore(
            store,
            eventHandler: eventHandler,
            autoReconnectAfterPairing: autoReconnectAfterPairing
        ) else {
            return nil
        }
        return GMLiveClient(client: loaded)
    }

    func makeClient(
        eventHandler: any GMEventHandler,
        autoReconnectAfterPairing: Bool
    ) async -> any GMClientProtocol {
        let client = await GMClient(
            eventHandler: eventHandler,
            autoReconnectAfterPairing: autoReconnectAfterPairing
        )
        return GMLiveClient(client: client)
    }
}

@MainActor
final class GMAppModel: ObservableObject {
    enum Screen: Equatable {
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
    @Published private(set) var pushConfiguration: GMPushConfiguration = .default
    @Published private(set) var pushRegistrationStatusText: String = ""
    @Published private(set) var backgroundSyncStatusText: String = ""
    @Published private(set) var backgroundSyncLastRunAt: Date?
    @Published private(set) var isBackgroundSyncRunning: Bool = false

    private let store: AuthDataStore
    private let eventHandler: GMEventStreamHandler
    private let cache: GMCacheStore
    private let clientFactory: any GMClientFactoryProtocol

    private var client: (any GMClientProtocol)?
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var refreshConversationsTask: Task<Void, Never>?
    private var refreshMessagesTask: Task<Void, Never>?
    private var pushRegistrationTask: Task<Void, Never>?
    private var backgroundSyncSchedulerTask: Task<Void, Never>?

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
    private var reconnectAttempts: Int = 0
    private var hasStarted: Bool = false

    private static let lastSelectedConversationKey = "gm_last_selected_conversation_id"

    init(
        store: AuthDataStore? = nil,
        clientFactory: (any GMClientFactoryProtocol)? = nil
    ) {
        GMPreferences.registerDefaults()
        self.store = store ?? Self.makeDefaultStore()
        self.eventHandler = GMEventStreamHandler()
        self.cache = GMCacheStore(rootURL: self.store.directory.appendingPathComponent("Cache", isDirectory: true))
        self.clientFactory = clientFactory ?? GMLiveClientFactory()
        self.pushConfiguration = GMPushConfiguration.loadFromDefaults()
        self.pushRegistrationStatusText = UserDefaults.standard.string(forKey: GMPreferences.pushRegistrationStatus) ?? ""
        self.backgroundSyncStatusText = UserDefaults.standard.string(forKey: GMPreferences.backgroundSyncStatus) ?? ""
        self.backgroundSyncLastRunAt = UserDefaults.standard.object(forKey: GMPreferences.backgroundSyncLastRunAt) as? Date
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
        hasStarted = true

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
            if let loaded = try await clientFactory.loadFromStore(
                store,
                eventHandler: eventHandler,
                autoReconnectAfterPairing: false
            ) {
                client = loaded

                guard await loaded.isLoggedIn else {
                    await handleSessionInvalidation(
                        reason: "Stored session is no longer valid. Pair again.",
                        clearError: false
                    )
                    GMLog.warn(.app, "Stored auth exists but isLoggedIn=false; forcing re-pair")
                    return
                }

                screen = .ready
                GMLog.info(.app, "Loaded auth from store, bootstrapping")
                do {
                    try await connectAndBootstrap()
                } catch {
                    if Self.shouldInvalidateSession(for: error) {
                        await handleSessionInvalidation(
                            reason: "Session expired. Pair your phone again.",
                            clearError: false
                        )
                        return
                    }
                    connectionStatusText = "Disconnected"
                    errorMessage = "Failed to connect: \(error.localizedDescription)"
                    GMLog.error(.app, "Failed to connect: \(error.localizedDescription)")
                    scheduleReconnect(reason: "Reconnecting...", baseDelaySeconds: 1, resetAttempts: true)
                }
            } else {
                screen = .needsPairing
                connectionStatusText = ""
                GMLog.info(.app, "No auth in store; needs pairing")
            }
        } catch {
            if Self.shouldInvalidateSession(for: error) {
                await handleSessionInvalidation(
                    reason: "Stored session became invalid. Pair your phone again.",
                    clearError: false
                )
                return
            }
            screen = .needsPairing
            connectionStatusText = ""
            errorMessage = "Failed to load auth: \(error.localizedDescription)"
            GMLog.error(.app, "Failed to load auth: \(error.localizedDescription)")
        }

        restartBackgroundSyncSchedulerIfNeeded()
    }

    func startPairing() async {
        errorMessage = nil
        typingIndicatorText = nil

        pairingQRCodeURL = nil
        pairingStatusText = "Requesting QR code..."
        connectionStatusText = ""
        screen = .pairing
        backgroundSyncSchedulerTask?.cancel()
        backgroundSyncSchedulerTask = nil
        pushRegistrationTask?.cancel()
        pushRegistrationTask = nil
        GMLog.info(.app, "Start pairing")

        let newClient = await clientFactory.makeClient(
            eventHandler: eventHandler,
            autoReconnectAfterPairing: false
        )
        client = newClient

        do {
            let qr = try await newClient.startLogin()
            pairingQRCodeURL = qr
            pairingStatusText = "Scan this QR code in Google Messages on your phone."
            GMLog.info(.app, "Pairing QR received urlLen=\(qr.count)")

            pairingStatusText = "Waiting for phone to pair..."
            GMLog.info(.app, "Waiting for phone to pair")
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
        notifiedMessageIDs.removeAll(keepingCapacity: false)
        linkMetadataTasks.values.forEach { $0.cancel() }
        linkMetadataTasks.removeAll(keepingCapacity: false)
        linkMetadataMemory.removeAll(keepingCapacity: false)
        linkMetadataTasks.values.forEach { $0.cancel() }
        linkMetadataTasks.removeAll(keepingCapacity: false)
        linkMetadataMemory.removeAll(keepingCapacity: false)

        refreshConversationsTask?.cancel()
        refreshConversationsTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        refreshMessagesTask?.cancel()
        refreshMessagesTask = nil
        pushRegistrationTask?.cancel()
        pushRegistrationTask = nil
        backgroundSyncSchedulerTask?.cancel()
        backgroundSyncSchedulerTask = nil
        reconnectAttempts = 0

        messages = []
        messagesCursor = nil
        conversations = []
        selectedConversationID = nil

        if let client {
            do {
                try await client.unpair()
                GMLog.info(.app, "Unpaired session on logout")
            } catch {
                GMLog.warn(.app, "Unpair failed during logout: \(error.localizedDescription)")
            }
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

    func handleScenePhaseChange(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            GMLog.debug(.app, "Scene phase active")
            restartBackgroundSyncSchedulerIfNeeded()
            guard screen == .ready, let client else { return }
            if !(await client.isConnected) {
                scheduleReconnect(
                    reason: "Resuming connection...",
                    baseDelaySeconds: 0.7,
                    resetAttempts: true
                )
            }
        case .inactive:
            GMLog.debug(.app, "Scene phase inactive")
            restartBackgroundSyncSchedulerIfNeeded()
        case .background:
            GMLog.debug(.app, "Scene phase background")
            restartBackgroundSyncSchedulerIfNeeded()
        @unknown default:
            break
        }
    }

    func updatePushConfiguration(_ mutate: (inout GMPushConfiguration) -> Void) {
        var updated = pushConfiguration
        mutate(&updated)
        updated = updated.sanitized()
        if !updated.canAttemptRegistration() {
            updated.lastRegisteredFingerprint = nil
            updated.lastRegisteredAt = nil
        }
        guard updated != pushConfiguration else { return }
        pushConfiguration = updated
        persistPushConfiguration()
        schedulePushRegistration(reason: "config_changed", force: false, debounceSeconds: 0.8)
        restartBackgroundSyncSchedulerIfNeeded()
    }

    func registerPushNow() async {
        await registerPushIfNeeded(force: true, reason: "manual")
    }

    func runBackgroundSyncNow() async {
        await runBackgroundSync(reason: "manual", userInitiated: true)
    }

    func refreshConversations() async {
        guard let client else { return }
        GMLog.debug(.network, "Refreshing conversations (network)")
        do {
            conversations = try await fetchAllConversations(client: client, pageSize: 75, maxPages: 30)
            await cache.saveConversations(conversations)
            if let first = conversations.first {
                GMLog.info(.network, "Refreshed conversations count=\(conversations.count) sample.lastMessageTimestamp=\(describeTimestamp(first.lastMessageTimestamp))")
            } else {
                GMLog.info(.network, "Refreshed conversations count=0")
            }

            let previousSelection = selectedConversationID
            let resolvedSelection = resolvePreferredConversationID(
                previousSelection: previousSelection,
                conversations: conversations
            )
            let selectionChanged = previousSelection != resolvedSelection
            selectedConversationID = resolvedSelection
            if let resolvedSelection {
                UserDefaults.standard.set(resolvedSelection, forKey: Self.lastSelectedConversationKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastSelectedConversationKey)
            }

            if selectionChanged || (messages.isEmpty && resolvedSelection != nil) {
                await loadMessagesForSelected(reset: true, forceNetwork: false)
            }
        } catch {
            if Self.shouldInvalidateSession(for: error) {
                await handleSessionInvalidation(
                    reason: "Session expired while refreshing conversations. Pair your phone again.",
                    clearError: false
                )
                return
            }
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
            if await handlePossibleSessionInvalidation(
                error,
                reason: "Session expired while loading messages. Pair your phone again."
            ) {
                return
            }
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
                if await handlePossibleSessionInvalidation(
                    error,
                    reason: "Session expired while syncing messages. Pair your phone again."
                ) {
                    return
                }
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
            if await handlePossibleSessionInvalidation(
                error,
                reason: "Session expired while sending. Pair your phone again."
            ) {
                return
            }
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
            if await handlePossibleSessionInvalidation(
                error,
                reason: "Session expired while sending media. Pair your phone again."
            ) {
                return
            }
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
        client: any GMClientProtocol
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
            let resp = try await client.getOrCreateConversation(
                numbers: [normalized],
                rcsGroupName: nil,
                createRCSGroup: false
            )
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
            if await handlePossibleSessionInvalidation(
                error,
                reason: "Session expired while creating conversation. Pair your phone again."
            ) {
                return
            }
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
            if await handlePossibleSessionInvalidation(
                error,
                reason: "Session expired while deleting message. Pair your phone again."
            ) {
                return
            }
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
            if await handlePossibleSessionInvalidation(
                error,
                reason: "Session expired while sending reaction. Pair your phone again."
            ) {
                return
            }
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
            if await handlePossibleSessionInvalidation(
                error,
                reason: "Session expired while updating conversation. Pair your phone again."
            ) {
                return
            }
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
            if await handlePossibleSessionInvalidation(
                error,
                reason: "Session expired while updating conversation. Pair your phone again."
            ) {
                return
            }
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
        reconnectAttempts = 0
        GMLog.info(.app, "Connected")

        await refreshConversations()
        schedulePushRegistration(reason: "startup", force: false, debounceSeconds: 0.2)
        restartBackgroundSyncSchedulerIfNeeded()
    }

    private func scheduleConversationsRefresh() {
        refreshConversationsTask?.cancel()
        refreshConversationsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            await self?.refreshConversations()
        }
    }

    private func scheduleReconnect(
        reason: String,
        baseDelaySeconds: TimeInterval,
        resetAttempts: Bool
    ) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            if resetAttempts {
                self.reconnectAttempts = 0
            }

            while !Task.isCancelled {
                self.reconnectAttempts += 1
                let attempt = self.reconnectAttempts
                let delay = Self.reconnectDelaySeconds(
                    attempt: attempt,
                    baseDelaySeconds: baseDelaySeconds
                )
                self.connectionStatusText = reason
                GMLog.warn(.app, "Reconnect scheduled attempt=\(attempt) delay=\(String(format: "%.2f", delay))s reason=\(reason)")
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }

                guard let client = self.client else { return }
                do {
                    try await client.reconnect()
                    self.connectionStatusText = "Connected"
                    self.errorMessage = nil
                    self.reconnectAttempts = 0
                    GMLog.info(.app, "Reconnected")
                    await self.refreshConversations()
                    await self.registerPushIfNeeded(force: false, reason: "reconnect")
                    self.restartBackgroundSyncSchedulerIfNeeded()
                    return
                } catch {
                    if Self.shouldInvalidateSession(for: error) {
                        await self.handleSessionInvalidation(
                            reason: "Session expired while reconnecting. Pair your phone again.",
                            clearError: false
                        )
                        return
                    }
                    self.connectionStatusText = "Disconnected"
                    self.errorMessage = "Reconnect failed (\(attempt)): \(error.localizedDescription)"
                    GMLog.error(.app, "Reconnect failed attempt=\(attempt): \(error.localizedDescription)")
                }
            }
        }
    }

    private func fetchAllConversations(
        client: any GMClientProtocol,
        pageSize: Int,
        maxPages: Int
    ) async throws -> [Conversations_Conversation] {
        var cursor: Client_Cursor?
        var all: [Conversations_Conversation] = []
        var page = 0

        while page < maxPages {
            let response = try await client.listConversationsPage(
                count: pageSize,
                folder: .inbox,
                cursor: cursor
            )
            page += 1

            all = Self.mergeConversations(existing: all, incoming: response.conversations)
            GMLog.info(
                .network,
                "Conversations page=\(page) pageCount=\(response.conversations.count) total=\(all.count) cursor=\(response.hasCursor ? "yes" : "no")"
            )

            guard response.hasCursor else { break }
            cursor = response.cursor
        }

        if page == maxPages, cursor != nil {
            GMLog.warn(.network, "Conversation pagination hit page cap=\(maxPages); list may be truncated")
        }

        return all.sorted(by: { $0.lastMessageTimestamp > $1.lastMessageTimestamp })
    }

    private func resolvePreferredConversationID(
        previousSelection: String?,
        conversations: [Conversations_Conversation]
    ) -> String? {
        if let previousSelection,
           conversations.contains(where: { $0.conversationID == previousSelection })
        {
            return previousSelection
        }

        let savedID = UserDefaults.standard.string(forKey: Self.lastSelectedConversationKey)
        if let savedID,
           conversations.contains(where: { $0.conversationID == savedID })
        {
            return savedID
        }

        return conversations.first?.conversationID
    }

    private func schedulePushRegistration(
        reason: String,
        force: Bool,
        debounceSeconds: TimeInterval
    ) {
        pushRegistrationTask?.cancel()
        pushRegistrationTask = Task { [weak self] in
            guard let self else { return }
            if debounceSeconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounceSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
            }
            await self.registerPushIfNeeded(force: force, reason: reason)
        }
    }

    private func registerPushIfNeeded(force: Bool, reason: String) async {
        guard let client else {
            if force {
                setPushRegistrationStatus("Push registration failed: not connected.")
            }
            return
        }
        guard pushConfiguration.enabled else {
            if force {
                setPushRegistrationStatus("Push registration skipped: disabled.")
            }
            return
        }

        do {
            let keys = try pushConfiguration.makePushKeys()
            let fingerprint = try pushConfiguration.registrationFingerprint()
            if !force, pushConfiguration.lastRegisteredFingerprint == fingerprint {
                GMLog.debug(.network, "Skip push registration (unchanged) reason=\(reason)")
                return
            }

            GMLog.info(.network, "Registering push reason=\(reason) endpointHost=\(URL(string: keys.url)?.host ?? "?")")
            try await client.registerPush(keys: keys)

            pushConfiguration.lastRegisteredFingerprint = fingerprint
            pushConfiguration.lastRegisteredAt = Date()
            persistPushConfiguration()
            let timestamp = pushConfiguration.lastRegisteredAt?
                .formatted(date: .numeric, time: .shortened) ?? "now"
            setPushRegistrationStatus("Push registered (\(timestamp)).")
            GMLog.info(.network, "Push registration succeeded reason=\(reason)")
        } catch {
            if Self.shouldInvalidateSession(for: error) {
                await handleSessionInvalidation(
                    reason: "Session expired while registering push. Pair your phone again.",
                    clearError: false
                )
                return
            }
            setPushRegistrationStatus("Push registration failed: \(error.localizedDescription)")
            if force {
                errorMessage = "Push registration failed: \(error.localizedDescription)"
            }
            GMLog.error(.network, "Push registration failed reason=\(reason): \(error.localizedDescription)")
        }
    }

    private func runBackgroundSync(reason: String, userInitiated: Bool) async {
        if isBackgroundSyncRunning { return }
        if !userInitiated, !pushConfiguration.backgroundSyncEnabled { return }

        guard let client else {
            if userInitiated {
                setBackgroundSyncStatus("Background sync failed: not connected.")
            }
            return
        }

        isBackgroundSyncRunning = true
        defer { isBackgroundSyncRunning = false }
        let shouldRetryUncleanExit = true

        for attempt in 1...2 {
            do {
                GMLog.info(.network, "Background sync start reason=\(reason) attempt=\(attempt)")
                try await client.connectBackground()
                backgroundSyncLastRunAt = Date()
                UserDefaults.standard.set(backgroundSyncLastRunAt, forKey: GMPreferences.backgroundSyncLastRunAt)
                let timestamp = backgroundSyncLastRunAt?
                    .formatted(date: .numeric, time: .shortened) ?? "now"
                setBackgroundSyncStatus("Background sync succeeded (\(timestamp)).")
                GMLog.info(.network, "Background sync succeeded reason=\(reason) attempt=\(attempt)")
                return
            } catch {
                if Self.shouldInvalidateSession(for: error) {
                    await handleSessionInvalidation(
                        reason: "Session expired during background sync. Pair your phone again.",
                        clearError: false
                    )
                    return
                }

                let isUnclean = (error as? GMClientError) == .backgroundPollingExitedUncleanly
                if shouldRetryUncleanExit && isUnclean && attempt == 1 {
                    let jitter = Double.random(in: 0.4...1.3)
                    GMLog.warn(.network, "Background sync unclean exit; retrying after \(String(format: "%.2f", jitter))s")
                    try? await Task.sleep(nanoseconds: UInt64(jitter * 1_000_000_000))
                    continue
                }

                let text = "Background sync failed: \(error.localizedDescription)"
                setBackgroundSyncStatus(text)
                if userInitiated {
                    errorMessage = text
                }
                GMLog.error(.network, "Background sync failed reason=\(reason) attempt=\(attempt): \(error.localizedDescription)")
                return
            }
        }
    }

    private func restartBackgroundSyncSchedulerIfNeeded() {
        backgroundSyncSchedulerTask?.cancel()
        backgroundSyncSchedulerTask = nil

        guard hasStarted else { return }
        guard pushConfiguration.backgroundSyncEnabled else { return }
        guard client != nil else { return }

        backgroundSyncSchedulerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let currentInterval = max(
                    GMPushConfiguration.minBackgroundSyncIntervalMinutes,
                    self.pushConfiguration.backgroundSyncIntervalMinutes
                )
                GMLog.debug(.network, "Background sync scheduler sleeping \(currentInterval)m")
                do {
                    try await Task.sleep(nanoseconds: UInt64(currentInterval) * 60 * 1_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self.runBackgroundSync(reason: "scheduled_\(currentInterval)m", userInitiated: false)
            }
        }
    }

    private func persistPushConfiguration() {
        pushConfiguration.saveToDefaults()
    }

    private func setPushRegistrationStatus(_ text: String) {
        pushRegistrationStatusText = text
        UserDefaults.standard.set(text, forKey: GMPreferences.pushRegistrationStatus)
    }

    private func setBackgroundSyncStatus(_ text: String) {
        backgroundSyncStatusText = text
        UserDefaults.standard.set(text, forKey: GMPreferences.backgroundSyncStatus)
    }

    private func handleSessionInvalidation(reason: String, clearError: Bool) async {
        GMLog.warn(.app, "Session invalidation reason=\(reason)")
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
        refreshConversationsTask?.cancel()
        refreshConversationsTask = nil
        refreshMessagesTask?.cancel()
        refreshMessagesTask = nil
        pushRegistrationTask?.cancel()
        pushRegistrationTask = nil
        backgroundSyncSchedulerTask?.cancel()
        backgroundSyncSchedulerTask = nil
        markReadTask?.cancel()
        markReadTask = nil
        outgoingTypingStopTask?.cancel()
        outgoingTypingStopTask = nil
        remoteTypingClearTask?.cancel()
        remoteTypingClearTask = nil
        linkPrefetchTask?.cancel()
        linkPrefetchTask = nil

        if let client {
            await client.disconnect()
        }
        client = nil

        do {
            try store.delete()
        } catch {
            GMLog.warn(.app, "Failed to delete auth store during invalidation: \(error.localizedDescription)")
        }
        await cache.clearAll()

        UserDefaults.standard.removeObject(forKey: Self.lastSelectedConversationKey)
        pairingQRCodeURL = nil
        pairingStatusText = ""
        typingIndicatorText = nil
        outgoingTypingIsActive = false
        outgoingTypingConversationID = nil
        messages = []
        messagesCursor = nil
        conversations = []
        selectedConversationID = nil
        phoneSettings = nil
        connectionStatusText = ""
        screen = .needsPairing
        if clearError {
            errorMessage = nil
        } else {
            errorMessage = reason
        }
    }

    private func handlePossibleSessionInvalidation(_ error: Error, reason: String) async -> Bool {
        guard Self.shouldInvalidateSession(for: error) else { return false }
        await handleSessionInvalidation(reason: reason, clearError: false)
        return true
    }

    nonisolated static func shouldInvalidateSession(for error: Error) -> Bool {
        if let clientError = error as? GMClientError, clientError == .notLoggedIn {
            return true
        }
        if let httpError = error as? GMHTTPError {
            if case .httpError(let statusCode, _) = httpError {
                return isAuthInvalidatingStatusCode(statusCode)
            }
        }
        if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
            return true
        }
        return false
    }

    nonisolated static func isAuthInvalidatingStatusCode(_ statusCode: Int) -> Bool {
        statusCode == 401 || statusCode == 403
    }

    nonisolated static func reconnectDelaySeconds(
        attempt: Int,
        baseDelaySeconds: TimeInterval
    ) -> TimeInterval {
        let safeAttempt = max(1, attempt)
        let exp = min(pow(2.0, Double(safeAttempt - 1)), 64.0)
        let raw = baseDelaySeconds * exp
        let capped = min(90.0, max(baseDelaySeconds, raw))
        let jitter = Double.random(in: 0...(min(1.2, capped * 0.25)))
        return capped + jitter
    }

    nonisolated static func mergeConversations(
        existing: [Conversations_Conversation],
        incoming: [Conversations_Conversation]
    ) -> [Conversations_Conversation] {
        guard !incoming.isEmpty else { return existing }

        var map: [String: Conversations_Conversation] = [:]
        map.reserveCapacity(existing.count + incoming.count)
        for conv in existing where !conv.conversationID.isEmpty {
            map[conv.conversationID] = conv
        }

        for conv in incoming where !conv.conversationID.isEmpty {
            guard let previous = map[conv.conversationID] else {
                map[conv.conversationID] = conv
                continue
            }
            if conv.lastMessageTimestamp >= previous.lastMessageTimestamp {
                map[conv.conversationID] = conv
            }
        }
        return Array(map.values)
    }

    func handle(_ event: GMEvent) async {
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
                schedulePushRegistration(reason: "pair_success", force: false, debounceSeconds: 0.2)
                restartBackgroundSyncSchedulerIfNeeded()
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
            connectionStatusText = "Reconnecting..."
            self.errorMessage = "Temporary listen error: \(error.localizedDescription)"
            GMLog.warn(.events, "Event listenTemporaryError: \(error.localizedDescription)")

        case .listenFatalError(let error):
            scheduleReconnect(reason: "Reconnecting...", baseDelaySeconds: 1, resetAttempts: false)
            connectionStatusText = "Reconnecting..."
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
            await handleSessionInvalidation(
                reason: "Google account session ended. Pair your phone again.",
                clearError: false
            )
            GMLog.warn(.events, "Event gaiaLoggedOut")

        case .accountChange:
            break

        case .requestError(let info):
            errorMessage = "Request error (\(info.action))"
            GMLog.error(.events, "Event requestError action=\(info.action)")

        case .httpError(let info):
            if Self.isAuthInvalidatingStatusCode(info.statusCode) {
                await handleSessionInvalidation(
                    reason: "Authentication failed (\(info.statusCode)). Pair your phone again.",
                    clearError: false
                )
                return
            }
            errorMessage = "HTTP error (\(info.statusCode)) (\(info.action))"
            GMLog.error(.events, "Event httpError action=\(info.action) status=\(info.statusCode)")

        case .authTokenRefreshed:
            do {
                try await client?.saveAuthData(to: store)
                GMLog.debug(.events, "Persisted auth after token refresh")
                schedulePushRegistration(reason: "auth_token_refreshed", force: false, debounceSeconds: 0.5)
            } catch {
                GMLog.warn(.events, "Failed to persist auth after token refresh: \(error.localizedDescription)")
            }
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
        let conversation = conversations.first(where: { $0.conversationID == msg.conversationID })

        let senderName = notificationSenderDisplayName(for: msg, conversation: conversation)
        let conversationName = notificationConversationDisplayName(conversation)
        let isGroup = isGroupConversation(conversation)
        let subtitle: String? = {
            guard isGroup else { return nil }
            guard let conversationName else { return "Group message" }
            return conversationName == senderName ? "Group message" : conversationName
        }()

        let body = notificationBody(
            for: msg,
            previewEnabled: previewEnabled,
            senderName: senderName,
            conversationName: conversationName
        )

        await GMNotifications.postMessageNotification(
            identifier: id,
            threadIdentifier: msg.conversationID,
            title: senderName,
            subtitle: subtitle,
            body: body,
            playSound: playSound
        )
    }

    private func notificationSenderDisplayName(
        for msg: Conversations_Message,
        conversation: Conversations_Conversation?
    ) -> String {
        if msg.hasSenderParticipant,
           let senderName = participantName(msg.senderParticipant),
           !senderName.isEmpty
        {
            return senderName
        }

        if let conversation {
            if let participant = conversation.participants.first(where: { !$0.isMe }),
               let participantDisplayName = participantName(participant),
               !participantDisplayName.isEmpty
            {
                return participantDisplayName
            }

            let namedConversation = conversation.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !namedConversation.isEmpty {
                return namedConversation
            }
        }

        return "Message"
    }

    private func notificationConversationDisplayName(_ conversation: Conversations_Conversation?) -> String? {
        guard let conversation else { return nil }

        let namedConversation = conversation.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !namedConversation.isEmpty {
            return namedConversation
        }

        let participantNames = uniqueNames(
            conversation.participants
                .filter { !$0.isMe }
                .compactMap(participantName)
        )

        guard participantNames.count > 1 else { return nil }
        return participantNames.prefix(3).joined(separator: ", ")
    }

    private func isGroupConversation(_ conversation: Conversations_Conversation?) -> Bool {
        guard let conversation else { return false }
        return conversation.participants.filter { !$0.isMe }.count > 1
    }

    private func notificationBody(
        for msg: Conversations_Message,
        previewEnabled: Bool,
        senderName: String,
        conversationName: String?
    ) -> String {
        guard previewEnabled else {
            if let conversationName, !conversationName.isEmpty, conversationName != senderName {
                return "New message in \(conversationName)"
            }
            return "New message"
        }

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
    }

    private func uniqueNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        ordered.reserveCapacity(names.count)

        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                ordered.append(trimmed)
            }
        }

        return ordered
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
