//
//  SwiftGMessagesApp.swift
//  SwiftGMessages
//
//  Created by Max Weinbach on 12/6/25.
//

import SwiftUI
import UserNotifications

@main
struct SwiftGMessagesApp: App {
    @StateObject private var model = GMAppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = GMNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .task {
                    await model.start()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    Task { await model.handleScenePhaseChange(newPhase) }
                }
                #if os(macOS)
                .frame(minWidth: 980, minHeight: 640)
                #endif
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(model)
        }
        #endif
    }
}
