import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

enum IMStyle {
    static let outgoingBubble = Color(red: 0.0, green: 0.48, blue: 1.0)

    static var incomingBubble: Color {
        #if canImport(AppKit)
        return Color(nsColor: .controlBackgroundColor)
        #elseif canImport(UIKit)
        return Color(uiColor: .secondarySystemBackground)
        #else
        return Color.gray.opacity(0.18)
        #endif
    }

    static var chatBackground: Color {
        #if canImport(AppKit)
        return Color(nsColor: .textBackgroundColor)
        #elseif canImport(UIKit)
        return Color(uiColor: .systemBackground)
        #else
        return Color.white
        #endif
    }

    static var composerBackground: Color {
        #if canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
        #elseif canImport(UIKit)
        return Color(uiColor: .systemBackground)
        #else
        return Color.white
        #endif
    }

    static func initials(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }

        let parts = trimmed
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .map(String.init)
            .filter { !$0.isEmpty }

        if parts.count >= 2 {
            let a = parts[0].prefix(1)
            let b = parts[1].prefix(1)
            return (a + b).uppercased()
        }

        let alnum = trimmed.filter { $0.isLetter || $0.isNumber }
        return String(alnum.prefix(2)).uppercased()
    }

    static func avatarColor(title: String, hexColor: String) -> Color {
        if let c = colorFromHex(hexColor) {
            return c
        }
        let hue = stableHue(title)
        return Color(hue: hue, saturation: 0.45, brightness: 0.85)
    }

    private static func stableHue(_ s: String) -> Double {
        // FNV-1a 32-bit -> hue
        var hash: UInt32 = 2166136261
        for b in s.utf8 {
            hash ^= UInt32(b)
            hash &*= 16777619
        }
        return Double(hash % 360) / 360.0
    }

    private static func colorFromHex(_ hex: String) -> Color? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = Int(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

struct AvatarView: View {
    let title: String
    let hexColor: String
    var size: CGFloat = 34

    var body: some View {
        let initials = IMStyle.initials(for: title)
        ZStack {
            Circle()
                .fill(IMStyle.avatarColor(title: title, hexColor: hexColor))
            Text(initials)
                .font(.system(size: max(10, size * 0.36), weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(title))
    }
}

