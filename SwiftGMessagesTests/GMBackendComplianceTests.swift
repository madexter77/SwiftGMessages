import Foundation
import GMProto
import LibGM
import Testing
@testable import SwiftGMessages

@MainActor
struct GMBackendComplianceTests {
    @Test
    func pushConfigParsesBase64AndBase64URL() {
        let bytes = Data([0xFB, 0xEF, 0x10, 0x11])
        let standard = bytes.base64EncodedString() // ++8QEQ==
        let urlSafe = standard
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        #expect(GMPushConfiguration.decodeBase64Flexible(standard) == bytes)
        #expect(GMPushConfiguration.decodeBase64Flexible(urlSafe) == bytes)
        #expect(GMPushConfiguration.decodeBase64Flexible("!!!!") == nil)
    }

    @Test
    func authInvalidationClassifierMatchesExpectedErrors() {
        #expect(GMAppModel.shouldInvalidateSession(for: GMClientError.notLoggedIn))
        #expect(GMAppModel.shouldInvalidateSession(for: GMHTTPError.httpError(statusCode: 401, body: nil)))
        #expect(GMAppModel.shouldInvalidateSession(for: GMHTTPError.httpError(statusCode: 403, body: nil)))
        #expect(!GMAppModel.shouldInvalidateSession(for: GMHTTPError.httpError(statusCode: 500, body: nil)))
    }

    @Test
    func mergeConversationsDedupesByIDKeepingNewestTimestamp() {
        var older = Conversations_Conversation()
        older.conversationID = "conv-a"
        older.lastMessageTimestamp = 10

        var newer = Conversations_Conversation()
        newer.conversationID = "conv-a"
        newer.lastMessageTimestamp = 20

        var other = Conversations_Conversation()
        other.conversationID = "conv-b"
        other.lastMessageTimestamp = 15

        let merged = GMAppModel.mergeConversations(
            existing: [older],
            incoming: [newer, other]
        )

        #expect(merged.count == 2)
        #expect(merged.first(where: { $0.conversationID == "conv-a" })?.lastMessageTimestamp == 20)
        #expect(merged.first(where: { $0.conversationID == "conv-b" })?.lastMessageTimestamp == 15)
    }

    @Test
    func startWithInvalidStoredSessionRoutesToPairing() async throws {
        let store = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let mockClient = MockClient(isLoggedIn: false)
        let factory = MockClientFactory(loadedClient: mockClient)
        let model = GMAppModel(store: store, clientFactory: factory)

        await model.start()

        #expect(model.screen == .needsPairing)
        #expect(model.errorMessage != nil)
    }

    @Test
    func listenTemporaryErrorDoesNotTriggerExplicitReconnect() async throws {
        let store = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let mockClient = MockClient(isLoggedIn: true)
        let factory = MockClientFactory(loadedClient: mockClient)
        let model = GMAppModel(store: store, clientFactory: factory)

        await model.start()
        await model.handle(.listenTemporaryError(NSError(domain: "Test", code: 1)))
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        let reconnectCalls = await mockClient.reconnectCallCount()
        #expect(reconnectCalls == 0)
    }

    @Test
    func pushRegistrationSkipsUnchangedConfigFingerprint() async throws {
        let store = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let mockClient = MockClient(isLoggedIn: true)
        let factory = MockClientFactory(loadedClient: mockClient)
        let model = GMAppModel(store: store, clientFactory: factory)

        await model.start()

        let p256dh = Data([1, 2, 3, 4]).base64EncodedString()
        let auth1 = Data([5, 6, 7, 8]).base64EncodedString()
        let auth2 = Data([9, 10, 11, 12]).base64EncodedString()

        model.updatePushConfiguration {
            $0.enabled = true
            $0.endpointURL = "https://push.example.test/endpoint"
            $0.p256dh = p256dh
            $0.auth = auth1
        }
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        #expect(await mockClient.registerPushCallCount() == 1)

        // No effective change -> no additional registration.
        model.updatePushConfiguration {
            $0.enabled = true
            $0.endpointURL = "https://push.example.test/endpoint"
            $0.p256dh = p256dh
            $0.auth = auth1
        }
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        #expect(await mockClient.registerPushCallCount() == 1)

        // Fingerprint change -> registration should run again.
        model.updatePushConfiguration {
            $0.auth = auth2
        }
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        #expect(await mockClient.registerPushCallCount() == 2)
    }

    @Test
    func backgroundSyncRetriesOnceAfterUncleanExit() async throws {
        let store = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let mockClient = MockClient(isLoggedIn: true)
        await mockClient.setConnectBackgroundBehaviors([.uncleanExit, .succeed])
        let factory = MockClientFactory(loadedClient: mockClient)
        let model = GMAppModel(store: store, clientFactory: factory)

        await model.start()
        await model.runBackgroundSyncNow()

        #expect(await mockClient.connectBackgroundCallCount() == 2)
        #expect(model.backgroundSyncStatusText.contains("succeeded"))
    }
}

private func makeTempStore() throws -> AuthDataStore {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("SwiftGMessagesTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return AuthDataStore(directoryURL: dir)
}

final class MockClientFactory: GMClientFactoryProtocol {
    let loadedClient: (any GMClientProtocol)?

    init(loadedClient: (any GMClientProtocol)?) {
        self.loadedClient = loadedClient
    }

    func loadFromStore(
        _ store: AuthDataStore,
        eventHandler: any GMEventHandler,
        autoReconnectAfterPairing: Bool
    ) async throws -> (any GMClientProtocol)? {
        loadedClient
    }

    func makeClient(
        eventHandler: any GMEventHandler,
        autoReconnectAfterPairing: Bool
    ) async -> any GMClientProtocol {
        loadedClient ?? MockClient(isLoggedIn: false)
    }
}

actor MockClient: GMClientProtocol {
    enum ConnectBackgroundBehavior: Sendable {
        case succeed
        case uncleanExit
        case fail
    }

    private var loggedIn: Bool
    private var connected: Bool

    private var reconnectCalls = 0
    private var registerPushCalls = 0
    private var connectBackgroundCalls = 0
    private var connectBackgroundBehaviors: [ConnectBackgroundBehavior] = []

    init(isLoggedIn: Bool, isConnected: Bool = true) {
        self.loggedIn = isLoggedIn
        self.connected = isConnected
    }

    func setConnectBackgroundBehaviors(_ values: [ConnectBackgroundBehavior]) {
        connectBackgroundBehaviors = values
    }

    func reconnectCallCount() -> Int { reconnectCalls }
    func registerPushCallCount() -> Int { registerPushCalls }
    func connectBackgroundCallCount() -> Int { connectBackgroundCalls }

    var isConnected: Bool {
        get async { connected }
    }

    var isLoggedIn: Bool {
        get async { loggedIn }
    }

    func connect() async throws {
        connected = true
    }

    func disconnect() async {
        connected = false
    }

    func reconnect() async throws {
        reconnectCalls += 1
        connected = true
    }

    func connectBackground() async throws {
        connectBackgroundCalls += 1
        if connectBackgroundBehaviors.isEmpty {
            return
        }
        let next = connectBackgroundBehaviors.removeFirst()
        switch next {
        case .succeed:
            return
        case .uncleanExit:
            throw GMClientError.backgroundPollingExitedUncleanly
        case .fail:
            throw NSError(domain: "Mock", code: 2)
        }
    }

    func startLogin() async throws -> String {
        "mock-qr"
    }

    func saveAuthData(to store: AuthDataStore) async throws {}
    func unpair() async throws {}

    func listConversationsPage(
        count: Int,
        folder: Client_ListConversationsRequest.Folder,
        cursor: Client_Cursor?
    ) async throws -> Client_ListConversationsResponse {
        Client_ListConversationsResponse()
    }

    func fetchMessages(
        conversationID: String,
        count: Int,
        cursor: Client_Cursor?
    ) async throws -> (messages: [Conversations_Message], cursor: Client_Cursor?) {
        ([], nil)
    }

    func fetchMessagesPage(
        conversationID: String,
        count: Int,
        cursor: Client_Cursor?
    ) async throws -> Client_ListMessagesResponse {
        Client_ListMessagesResponse()
    }

    func sendMessage(_ request: Client_SendMessageRequest) async throws -> Client_SendMessageResponse {
        var response = Client_SendMessageResponse()
        response.status = .success
        return response
    }

    func uploadMedia(data: Data, fileName: String, mimeType: String) async throws -> Conversations_MediaContent {
        Conversations_MediaContent()
    }

    func downloadMedia(mediaID: String, decryptionKey: Data) async throws -> Data {
        Data()
    }

    func deleteMessage(messageID: String) async throws -> Bool {
        true
    }

    func sendReaction(
        messageID: String,
        emoji: String,
        action: Client_SendReactionRequest.Action
    ) async throws {}

    func updateConversationStatus(
        conversationID: String,
        status: Conversations_ConversationStatus
    ) async throws {}

    func setConversationMuted(conversationID: String, isMuted: Bool) async throws {}

    func getConversation(id conversationID: String) async throws -> Conversations_Conversation {
        var conv = Conversations_Conversation()
        conv.conversationID = conversationID
        return conv
    }

    func getOrCreateConversation(
        numbers: [String],
        rcsGroupName: String?,
        createRCSGroup: Bool
    ) async throws -> Client_GetOrCreateConversationResponse {
        var response = Client_GetOrCreateConversationResponse()
        var conv = Conversations_Conversation()
        conv.conversationID = "mock-conversation"
        response.conversation = conv
        return response
    }

    func markRead(conversationID: String, messageID: String) async throws {}

    func setTyping(conversationID: String, isTyping: Bool) async throws {}

    func registerPush(keys: PushKeys) async throws {
        registerPushCalls += 1
    }
}
