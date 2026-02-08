import SwiftUI

#if os(macOS)
import AppKit
#endif

struct PairingRootView: View {
    @EnvironmentObject private var model: GMAppModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            IMStyle.chatBackground.ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(IMStyle.outgoingBubble)

                    Text("Swift Google Messages")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))

                    Text("Pair your phone to start syncing conversations.")
                        .foregroundStyle(.secondary)
                }

                Group {
                    if let url = model.pairingQRCodeURL, !url.isEmpty {
                        QRCodeView(text: url)
                            .frame(width: 270, height: 270)
                            .padding(12)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(.secondary.opacity(0.12))
                            }

                        VStack(spacing: 10) {
                            Text(url)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(3)

                            HStack(spacing: 10) {
                                Button("Copy URL") { copyToClipboard(url) }
                                Button("Open URL") {
                                    if let u = URL(string: url) { openURL(u) }
                                }
                            }
                        }
                        .frame(maxWidth: 560)
                    } else {
                        VStack(spacing: 12) {
                            Text("Not paired")
                                .font(.headline)
                            Text("Click Start Pairing, then scan the QR code in the Google Messages app on your phone.")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 560)

                            Button {
                                Task { await model.startPairing() }
                            } label: {
                                Text("Start Pairing")
                                    .frame(minWidth: 160)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(IMStyle.outgoingBubble)
                            .controlSize(.large)
                        }
                    }
                }

                if !model.pairingStatusText.isEmpty {
                    Text(model.pairingStatusText)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func copyToClipboard(_ s: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #endif
    }
}
