import Foundation
import UserNotifications

@MainActor
final class GMNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = GMNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        var opts: UNNotificationPresentationOptions = [.banner, .list]
        if notification.request.content.sound != nil {
            opts.insert(.sound)
        }
        return opts
    }
}

enum GMNotifications {
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { cont in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                cont.resume(returning: settings.authorizationStatus)
            }
        }
    }

    static func requestAuthorizationIfNeeded() async -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await withCheckedContinuation { cont in
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    static func postMessageNotification(
        identifier: String,
        threadIdentifier: String?,
        title: String,
        subtitle: String?,
        body: String,
        playSound: Bool
    ) async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle, !subtitle.isEmpty {
            content.subtitle = subtitle
        }
        content.body = body
        content.categoryIdentifier = "gm.message.incoming"
        content.targetContentIdentifier = identifier
        content.summaryArgument = title
        content.summaryArgumentCount = 1
        content.interruptionLevel = .active
        content.relevanceScore = 1.0
        if let threadIdentifier, !threadIdentifier.isEmpty {
            content.threadIdentifier = threadIdentifier
        }
        if playSound {
            content.sound = .default
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            // Best-effort; ignore.
        }
    }
}
