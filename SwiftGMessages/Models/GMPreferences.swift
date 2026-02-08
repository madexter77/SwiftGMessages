import Foundation

enum GMPreferences {
    // Notifications
    static let notificationsEnabled = "gm_pref_notifications_enabled"
    static let notificationsPreview = "gm_pref_notifications_preview"
    static let notificationsWhenActive = "gm_pref_notifications_when_active"
    static let notificationsSound = "gm_pref_notifications_sound"

    // Messaging
    static let showTypingIndicators = "gm_pref_show_typing_indicators"
    static let sendTypingIndicators = "gm_pref_send_typing_indicators"
    static let sendReadReceipts = "gm_pref_send_read_receipts"

    // Media
    static let autoLoadImagePreviews = "gm_pref_auto_load_image_previews"

    // Links
    static let linkPreviewsEnabled = "gm_pref_link_previews_enabled"
    static let autoLoadLinkPreviews = "gm_pref_auto_load_link_previews"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            notificationsEnabled: true,
            notificationsPreview: true,
            notificationsWhenActive: false,
            notificationsSound: true,

            showTypingIndicators: true,
            sendTypingIndicators: true,
            sendReadReceipts: true,

            autoLoadImagePreviews: true,

            linkPreviewsEnabled: true,
            autoLoadLinkPreviews: true,
        ])
    }
}
