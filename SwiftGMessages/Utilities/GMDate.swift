import Foundation

func gmDate(from ts: Int64) -> Date {
    // Google Messages timestamps are usually Unix epoch in microseconds.
    // Some fields may arrive as seconds/ms/us/ns depending on the source.
    let absTS = ts >= 0 ? ts : -ts

    let seconds: TimeInterval
    if absTS >= 1_000_000_000_000_000_000 {         // ~1e18 (nanoseconds)
        seconds = TimeInterval(ts) / 1_000_000_000.0
    } else if absTS >= 1_000_000_000_000_000 {      // ~1e15 (microseconds)
        seconds = TimeInterval(ts) / 1_000_000.0
    } else if absTS >= 1_000_000_000_000 {          // ~1e12 (milliseconds)
        seconds = TimeInterval(ts) / 1_000.0
    } else {
        seconds = TimeInterval(ts)                  // seconds
    }

    return Date(timeIntervalSince1970: seconds)
}
