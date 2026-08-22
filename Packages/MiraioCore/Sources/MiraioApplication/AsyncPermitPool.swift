import Foundation

package actor AsyncPermitPool {
  private struct Waiter {
    let id: UUID
    let continuation: CheckedContinuation<Void, any Error>
  }

  private var available: Int
  private var waiters: [Waiter] = []
  private var cancelled: Set<UUID> = []

  package init(limit: Int) {
    precondition(limit > 0)
    available = limit
  }

  package func withPermit<Value: Sendable>(
    _ operation: @Sendable () async throws -> Value
  ) async throws -> Value {
    try await acquire()
    defer { release() }
    return try await operation()
  }

  private func acquire() async throws {
    if available > 0 {
      available -= 1
      return
    }

    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        if Task.isCancelled || cancelled.remove(id) != nil {
          continuation.resume(throwing: CancellationError())
        } else {
          waiters.append(Waiter(id: id, continuation: continuation))
        }
      }
    } onCancel: {
      Task { await self.cancel(id) }
    }
  }

  private func release() {
    if waiters.isEmpty {
      available += 1
    } else {
      waiters.removeFirst().continuation.resume()
    }
  }

  private func cancel(_ id: UUID) {
    if let index = waiters.firstIndex(where: { $0.id == id }) {
      waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    } else {
      cancelled.insert(id)
    }
  }
}
