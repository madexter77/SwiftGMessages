import CryptoKit
import Foundation
import GMProto
@preconcurrency import SwiftProtobuf
import UniformTypeIdentifiers

/// Best-effort disk + memory cache for fast conversation switching.
///
/// Stores protobuf-serialized responses under the app's Application Support directory.
actor GMCacheStore {
    private let rootURL: URL
    private let messagesDirURL: URL
    private let mediaDirURL: URL
    private let linksDirURL: URL
    private let conversationsFileURL: URL

    private var memoryConversations: [Conversations_Conversation]?
    private var memoryMessages: [String: Client_ListMessagesResponse] = [:]
    private var memoryMediaURLs: [String: URL] = [:]
    private var memoryLinkMetadata: [String: Data] = [:]

    private var pendingMessageWrites: [String: Task<Void, Never>] = [:]
    private var pendingConversationsWrite: Task<Void, Never>?

    init(rootURL: URL) {
        self.rootURL = rootURL
        self.messagesDirURL = rootURL.appendingPathComponent("messages", isDirectory: true)
        self.mediaDirURL = rootURL.appendingPathComponent("media", isDirectory: true)
        self.linksDirURL = rootURL.appendingPathComponent("links", isDirectory: true)
        self.conversationsFileURL = rootURL.appendingPathComponent("conversations.pb")
    }

    // MARK: - Conversations

    func loadConversations() -> [Conversations_Conversation]? {
        if let memoryConversations {
            return memoryConversations
        }

        guard let data = try? Data(contentsOf: conversationsFileURL) else {
            return nil
        }

        do {
            let resp = try Client_ListConversationsResponse(serializedBytes: data)
            memoryConversations = resp.conversations
            return resp.conversations
        } catch {
            // Corrupt cache; ignore.
            return nil
        }
    }

    func saveConversations(_ conversations: [Conversations_Conversation]) {
        memoryConversations = conversations

        pendingConversationsWrite?.cancel()
        pendingConversationsWrite = Task { [weak self] in
            // Debounce slightly to avoid thrashing when the UI triggers multiple refreshes.
            try? await Task.sleep(nanoseconds: 300_000_000)
            await self?.flushConversationsToDisk()
        }
    }

    private func flushConversationsToDisk() {
        guard let conversations = memoryConversations else { return }
        do {
            try ensureDirectories()

            var resp = Client_ListConversationsResponse()
            resp.conversations = conversations
            let data = try resp.serializedData()
            try data.write(to: conversationsFileURL, options: .atomic)
        } catch {
            // Best-effort cache.
        }
    }

    // MARK: - Messages

    func loadMessages(conversationID: String) -> (messages: [Conversations_Message], cursor: Client_Cursor?)? {
        if let resp = memoryMessages[conversationID] {
            return (resp.messages, resp.hasCursor ? resp.cursor : nil)
        }

        let fileURL = messagesFileURL(conversationID: conversationID)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        do {
            let resp = try Client_ListMessagesResponse(serializedBytes: data)
            memoryMessages[conversationID] = resp
            return (resp.messages, resp.hasCursor ? resp.cursor : nil)
        } catch {
            return nil
        }
    }

    func hasMessagesCache(conversationID: String) -> Bool {
        if memoryMessages[conversationID] != nil { return true }
        let url = messagesFileURL(conversationID: conversationID)
        return FileManager.default.fileExists(atPath: url.path)
    }

    func saveMessages(
        conversationID: String,
        messages: [Conversations_Message],
        cursor: Client_Cursor?
    ) {
        var resp = Client_ListMessagesResponse()
        resp.messages = messages
        if let cursor {
            resp.cursor = cursor
        }
        memoryMessages[conversationID] = resp

        scheduleMessageFlush(conversationID: conversationID)
    }

    func saveMessagesResponse(
        conversationID: String,
        response: Client_ListMessagesResponse
    ) {
        memoryMessages[conversationID] = response
        scheduleMessageFlush(conversationID: conversationID)
    }

    /// Update an existing cached conversation with an incoming message.
    ///
    /// For correctness and to avoid confusing partial threads, this only updates
    /// conversations that already have a messages cache.
    func upsertMessageIfCached(_ message: Conversations_Message) {
        let conversationID = message.conversationID
        guard hasMessagesCache(conversationID: conversationID) else { return }

        let current = memoryMessages[conversationID] ?? loadMessagesResponseFromDisk(conversationID: conversationID) ?? Client_ListMessagesResponse()
        var updated = current

        if let idx = updated.messages.firstIndex(where: { $0.messageID == message.messageID }) {
            // Replace in-place to support updates (delivery/read receipts, full-res media arriving later, etc.).
            updated.messages[idx] = message
        } else if !message.tmpID.isEmpty,
                  let idx = updated.messages.firstIndex(where: { !$0.tmpID.isEmpty && $0.tmpID == message.tmpID })
        {
            // Outgoing remote echo can arrive with a new messageID but the same tmpID.
            updated.messages[idx] = message
        } else {
            updated.messages.append(message)
        }
        updated.messages.sort(by: { $0.timestamp < $1.timestamp })

        memoryMessages[conversationID] = updated
        scheduleMessageFlush(conversationID: conversationID)
    }

    private func scheduleMessageFlush(conversationID: String) {
        pendingMessageWrites[conversationID]?.cancel()
        pendingMessageWrites[conversationID] = Task { [weak self] in
            // Debounce writes (incoming messages can arrive in bursts).
            try? await Task.sleep(nanoseconds: 500_000_000)
            await self?.flushMessagesToDisk(conversationID: conversationID)
        }
    }

    private func flushMessagesToDisk(conversationID: String) {
        guard let resp = memoryMessages[conversationID] else { return }
        do {
            try ensureDirectories()
            let data = try resp.serializedData()
            try data.write(to: messagesFileURL(conversationID: conversationID), options: .atomic)
        } catch {
            // Best-effort cache.
        }
    }

    private func loadMessagesResponseFromDisk(conversationID: String) -> Client_ListMessagesResponse? {
        let url = messagesFileURL(conversationID: conversationID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Client_ListMessagesResponse(serializedBytes: data)
    }

    // MARK: - Media

    func cachedMediaURL(mediaID: String) -> URL? {
        if let url = memoryMediaURLs[mediaID], FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        // Try any extension by scanning directory. This is cheap because we store at most one file per id.
        let key = Self.sha256Hex(mediaID)
        guard let items = try? FileManager.default.contentsOfDirectory(at: mediaDirURL, includingPropertiesForKeys: nil) else {
            return nil
        }
        let found = items.first(where: { $0.lastPathComponent.hasPrefix(key + ".") })
        if let found {
            memoryMediaURLs[mediaID] = found
        }
        return found
    }

    func storeMedia(
        data: Data,
        mediaID: String,
        mimeType: String,
        suggestedName: String?
    ) -> URL? {
        do {
            try ensureDirectories()

            let key = Self.sha256Hex(mediaID)
            let ext = UTType(mimeType: mimeType)?.preferredFilenameExtension
            let safeExt = (ext?.isEmpty == false) ? ext! : "bin"
            let fileName = "\(key).\(safeExt)"
            let url = mediaDirURL.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            memoryMediaURLs[mediaID] = url
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Link Metadata

    func loadLinkMetadataData(urlString: String) -> Data? {
        if let data = memoryLinkMetadata[urlString] {
            return data
        }

        let url = linkMetadataFileURL(urlString: urlString)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        memoryLinkMetadata[urlString] = data
        return data
    }

    func saveLinkMetadataData(urlString: String, data: Data) {
        memoryLinkMetadata[urlString] = data
        do {
            try ensureDirectories()
            try data.write(to: linkMetadataFileURL(urlString: urlString), options: .atomic)
        } catch {
            // Best-effort cache.
        }
    }

    // MARK: - Maintenance

    func clearAll() {
        pendingConversationsWrite?.cancel()
        pendingConversationsWrite = nil
        for (_, task) in pendingMessageWrites {
            task.cancel()
        }
        pendingMessageWrites.removeAll(keepingCapacity: false)

        memoryConversations = nil
        memoryMessages.removeAll(keepingCapacity: false)
        memoryMediaURLs.removeAll(keepingCapacity: false)
        memoryLinkMetadata.removeAll(keepingCapacity: false)

        try? FileManager.default.removeItem(at: rootURL)
    }

    // MARK: - Helpers

    private func messagesFileURL(conversationID: String) -> URL {
        let key = Self.sha256Hex(conversationID)
        return messagesDirURL.appendingPathComponent(key).appendingPathExtension("pb")
    }

    private func linkMetadataFileURL(urlString: String) -> URL {
        let key = Self.sha256Hex(urlString)
        return linksDirURL.appendingPathComponent(key).appendingPathExtension("lpmeta")
    }

    private func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: messagesDirURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mediaDirURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linksDirURL, withIntermediateDirectories: true)
    }

    private static func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
