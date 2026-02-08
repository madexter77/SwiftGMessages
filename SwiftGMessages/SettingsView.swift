import GMProto
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var model: GMAppModel

    @AppStorage(GMPreferences.notificationsEnabled) private var notificationsEnabled: Bool = true
    @AppStorage(GMPreferences.notificationsPreview) private var notificationsPreview: Bool = true
    @AppStorage(GMPreferences.notificationsWhenActive) private var notificationsWhenActive: Bool = false
    @AppStorage(GMPreferences.notificationsSound) private var notificationsSound: Bool = true

    @AppStorage(GMPreferences.showTypingIndicators) private var showTypingIndicators: Bool = true
    @AppStorage(GMPreferences.sendTypingIndicators) private var sendTypingIndicators: Bool = true
    @AppStorage(GMPreferences.sendReadReceipts) private var sendReadReceipts: Bool = true

    @AppStorage(GMPreferences.autoLoadImagePreviews) private var autoLoadImagePreviews: Bool = true
    @AppStorage(GMPreferences.linkPreviewsEnabled) private var linkPreviewsEnabled: Bool = true
    @AppStorage(GMPreferences.autoLoadLinkPreviews) private var autoLoadLinkPreviews: Bool = true

    @State private var systemNotificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled {
                            Task { await ensureNotificationPermission() }
                        }
                    }

                Toggle("Include message preview", isOn: $notificationsPreview)
                    .disabled(!notificationsEnabled)

                Toggle("Notify while app is active", isOn: $notificationsWhenActive)
                    .disabled(!notificationsEnabled)

                Toggle("Play sound", isOn: $notificationsSound)
                    .disabled(!notificationsEnabled)

                HStack {
                    Text("System permission")
                    Spacer()
                    Text(notificationStatusText(systemNotificationStatus))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button("Request Notification Permission") {
                    Task { await ensureNotificationPermission(forcePrompt: true) }
                }
                .disabled(!notificationsEnabled)
            }

            Section("Messaging") {
                Toggle("Show typing indicators", isOn: $showTypingIndicators)

                Toggle("Send typing indicators", isOn: $sendTypingIndicators)

                Toggle("Send read receipts (mark read)", isOn: $sendReadReceipts)

                Divider()

                if let rcs = model.phoneSettings?.rcssettings {
                    LabeledContent("Phone RCS enabled") { Text(rcs.isEnabled ? "Yes" : "No") }
                    LabeledContent("Phone send read receipts") { Text(rcs.sendReadReceipts ? "Yes" : "No") }
                    LabeledContent("Phone show typing indicators") { Text(rcs.showTypingIndicators ? "Yes" : "No") }
                    LabeledContent("Phone default SMS app") { Text(rcs.isDefaultSmsapp ? "Yes" : "No") }
                } else {
                    Text("Phone settings have not been received yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Media") {
                Toggle("Auto-load image previews", isOn: $autoLoadImagePreviews)
            }

            Section("Links") {
                Toggle("Show link previews", isOn: $linkPreviewsEnabled)
                Toggle("Auto-load link previews", isOn: $autoLoadLinkPreviews)
                    .disabled(!linkPreviewsEnabled)
            }

            Section("Debug") {
                LabeledContent("Connection") { Text(model.connectionStatusText.isEmpty ? "Unknown" : model.connectionStatusText) }

                if let version = model.phoneSettings?.bugleVersion, !version.isEmpty {
                    LabeledContent("Bugle version") { Text(version) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 520)
        .task {
            systemNotificationStatus = await GMNotifications.authorizationStatus()
        }
    }

    private func ensureNotificationPermission(forcePrompt: Bool = false) async {
        if forcePrompt {
            _ = await GMNotifications.requestAuthorizationIfNeeded()
        } else {
            _ = await GMNotifications.requestAuthorizationIfNeeded()
        }
        systemNotificationStatus = await GMNotifications.authorizationStatus()

        // If the user turned the toggle on but the system permission is denied, turn it back off.
        if notificationsEnabled, systemNotificationStatus == .denied {
            notificationsEnabled = false
        }
    }

    private func notificationStatusText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not determined"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
}
