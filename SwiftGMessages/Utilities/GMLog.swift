import Foundation
import os

enum GMLogCategory: String {
    case app
    case events
    case cache
    case media
    case dates
    case network
}

enum GMLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "SwiftGMessages"

    private static func logger(_ category: GMLogCategory) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    private static func stamp() -> String {
        // Keep this cheap and thread-safe (DateFormatter is not thread-safe).
        let t = Date().timeIntervalSince1970
        return String(format: "%.3f", t)
    }

    static func debug(_ category: GMLogCategory, _ message: String) {
        logger(category).debug("\(message, privacy: .public)")
        #if DEBUG
        print("[\(stamp())] [\(category.rawValue)] DEBUG: \(message)")
        #endif
    }

    static func info(_ category: GMLogCategory, _ message: String) {
        logger(category).info("\(message, privacy: .public)")
        #if DEBUG
        print("[\(stamp())] [\(category.rawValue)] INFO: \(message)")
        #endif
    }

    static func warn(_ category: GMLogCategory, _ message: String) {
        logger(category).warning("\(message, privacy: .public)")
        #if DEBUG
        print("[\(stamp())] [\(category.rawValue)] WARN: \(message)")
        #endif
    }

    static func error(_ category: GMLogCategory, _ message: String) {
        logger(category).error("\(message, privacy: .public)")
        #if DEBUG
        print("[\(stamp())] [\(category.rawValue)] ERROR: \(message)")
        #endif
    }
}
