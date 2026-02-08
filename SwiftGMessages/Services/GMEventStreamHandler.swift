import Foundation
import LibGM

/// Bridges LibGM's push-style callbacks into an AsyncStream for easy consumption in SwiftUI.
actor GMEventStreamHandler: GMEventHandler {
    private var continuation: AsyncStream<GMEvent>.Continuation?

    func makeStream(
        bufferingPolicy: AsyncStream<GMEvent>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<GMEvent> {
        AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            Task { self.installContinuation(continuation) }
        }
    }

    private func installContinuation(_ newContinuation: AsyncStream<GMEvent>.Continuation) {
        continuation?.finish()
        continuation = newContinuation
        continuation?.onTermination = { @Sendable _ in
            Task { await self.clearContinuation() }
        }
    }

    private func clearContinuation() {
        continuation = nil
    }

    func handleEvent(_ event: GMEvent) async {
        continuation?.yield(event)
    }
}

