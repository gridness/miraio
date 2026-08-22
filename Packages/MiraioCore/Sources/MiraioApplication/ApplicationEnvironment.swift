import Foundation

public struct ApplicationEnvironment: Sendable {
  public let now: @Sendable () -> Date
  public let makeAttemptID: @Sendable () -> UUID
  public let diagnostics: any RedactedDiagnostics
  public let lifecycle: LifecycleCapabilities

  public init(
    now: @escaping @Sendable () -> Date,
    makeAttemptID: @escaping @Sendable () -> UUID,
    diagnostics: any RedactedDiagnostics,
    lifecycle: LifecycleCapabilities
  ) {
    self.now = now
    self.makeAttemptID = makeAttemptID
    self.diagnostics = diagnostics
    self.lifecycle = lifecycle
  }
}

public struct LifecycleCapabilities: Sendable {
  let revalidateSubscription: @Sendable () async -> Void
  let checkpointWatchHistory: @Sendable () async -> Void
  let cancelNonessentialWork: @Sendable () async -> Void
  let releaseVolatileCaches: @Sendable () async -> Void
  let cancelProtectedWork: @Sendable () async -> Void
  let clearProtectedState: @Sendable () async -> Void

  public init(
    revalidateSubscription: @escaping @Sendable () async -> Void,
    checkpointWatchHistory: @escaping @Sendable () async -> Void,
    cancelNonessentialWork: @escaping @Sendable () async -> Void,
    releaseVolatileCaches: @escaping @Sendable () async -> Void,
    cancelProtectedWork: @escaping @Sendable () async -> Void,
    clearProtectedState: @escaping @Sendable () async -> Void
  ) {
    self.revalidateSubscription = revalidateSubscription
    self.checkpointWatchHistory = checkpointWatchHistory
    self.cancelNonessentialWork = cancelNonessentialWork
    self.releaseVolatileCaches = releaseVolatileCaches
    self.cancelProtectedWork = cancelProtectedWork
    self.clearProtectedState = clearProtectedState
  }
}
