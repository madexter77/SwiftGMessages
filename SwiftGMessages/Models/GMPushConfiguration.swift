import CryptoKit
import Foundation
import LibGM

struct GMPushConfiguration: Codable, Equatable {
    static let defaultBackgroundSyncIntervalMinutes = 15
    static let minBackgroundSyncIntervalMinutes = 5
    static let maxBackgroundSyncIntervalMinutes = 240

    var enabled: Bool
    var endpointURL: String
    var p256dh: String
    var auth: String
    var backgroundSyncEnabled: Bool
    var backgroundSyncIntervalMinutes: Int
    var lastRegisteredFingerprint: String?
    var lastRegisteredAt: Date?

    init(
        enabled: Bool = false,
        endpointURL: String = "",
        p256dh: String = "",
        auth: String = "",
        backgroundSyncEnabled: Bool = false,
        backgroundSyncIntervalMinutes: Int = GMPushConfiguration.defaultBackgroundSyncIntervalMinutes,
        lastRegisteredFingerprint: String? = nil,
        lastRegisteredAt: Date? = nil
    ) {
        self.enabled = enabled
        self.endpointURL = endpointURL
        self.p256dh = p256dh
        self.auth = auth
        self.backgroundSyncEnabled = backgroundSyncEnabled
        self.backgroundSyncIntervalMinutes = backgroundSyncIntervalMinutes
        self.lastRegisteredFingerprint = lastRegisteredFingerprint
        self.lastRegisteredAt = lastRegisteredAt
        sanitize()
    }

    static var `default`: GMPushConfiguration {
        GMPushConfiguration()
    }

    mutating func sanitize() {
        endpointURL = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        p256dh = Self.compactBase64LikeString(p256dh)
        auth = Self.compactBase64LikeString(auth)
        if backgroundSyncIntervalMinutes < Self.minBackgroundSyncIntervalMinutes {
            backgroundSyncIntervalMinutes = Self.minBackgroundSyncIntervalMinutes
        }
        if backgroundSyncIntervalMinutes > Self.maxBackgroundSyncIntervalMinutes {
            backgroundSyncIntervalMinutes = Self.maxBackgroundSyncIntervalMinutes
        }
    }

    func sanitized() -> GMPushConfiguration {
        var c = self
        c.sanitize()
        return c
    }

    func canAttemptRegistration() -> Bool {
        enabled && !endpointURL.isEmpty && !p256dh.isEmpty && !auth.isEmpty
    }

    func makePushKeys() throws -> PushKeys {
        let normalizedEndpoint = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEndpoint.isEmpty else {
            throw GMPushConfigurationError.invalidEndpointURL
        }
        guard URL(string: normalizedEndpoint) != nil else {
            throw GMPushConfigurationError.invalidEndpointURL
        }

        guard let p256dhData = Self.decodeBase64Flexible(p256dh) else {
            throw GMPushConfigurationError.invalidP256DH
        }
        guard let authData = Self.decodeBase64Flexible(auth) else {
            throw GMPushConfigurationError.invalidAuthSecret
        }

        return PushKeys(url: normalizedEndpoint, p256dh: p256dhData, auth: authData)
    }

    func registrationFingerprint() throws -> String {
        let keys = try makePushKeys()
        var data = Data()
        data.append(Data(keys.url.utf8))
        data.append(0)
        data.append(keys.p256dh)
        data.append(0)
        data.append(keys.auth)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func decodeBase64Flexible(_ value: String) -> Data? {
        let compact = compactBase64LikeString(value)
        guard !compact.isEmpty else { return nil }

        if let direct = Data(base64Encoded: compact) {
            return direct
        }

        var base64 = compact
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        return Data(base64Encoded: base64)
    }

    static func compactBase64LikeString(_ value: String) -> String {
        value.unicodeScalars
            .filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
            .map(String.init)
            .joined()
    }

    static func loadFromDefaults(_ defaults: UserDefaults = .standard) -> GMPushConfiguration {
        guard let raw = defaults.string(forKey: GMPreferences.pushConfigurationJSON),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(GMPushConfiguration.self, from: data)
        else {
            return .default
        }
        return decoded.sanitized()
    }

    func saveToDefaults(_ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(sanitized()),
              let raw = String(data: data, encoding: .utf8)
        else {
            return
        }
        defaults.set(raw, forKey: GMPreferences.pushConfigurationJSON)
    }
}

enum GMPushConfigurationError: LocalizedError {
    case invalidEndpointURL
    case invalidP256DH
    case invalidAuthSecret

    var errorDescription: String? {
        switch self {
        case .invalidEndpointURL:
            return "Push endpoint URL is invalid."
        case .invalidP256DH:
            return "Push p256dh key is invalid (expected base64/base64url)."
        case .invalidAuthSecret:
            return "Push auth secret is invalid (expected base64/base64url)."
        }
    }
}
