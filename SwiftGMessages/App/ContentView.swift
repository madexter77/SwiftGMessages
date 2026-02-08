//
//  ContentView.swift
//  SwiftGMessages
//
//  Created by Max Weinbach on 12/6/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: GMAppModel

    var body: some View {
        Group {
            switch model.screen {
            case .loading:
                LoadingView(status: model.connectionStatusText)
            case .needsPairing, .pairing:
                PairingRootView()
            case .ready:
                MessagesRootView()
            }
        }
        .alert("Error", isPresented: Binding(get: {
            model.errorMessage != nil
        }, set: { newValue in
            if !newValue { model.errorMessage = nil }
        })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct LoadingView: View {
    let status: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(status.isEmpty ? "Loading..." : status)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
