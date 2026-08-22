public enum ApplicationLifecycleCommand: Sendable, Equatable {
  case foregrounded
  case backgrounding
  case memoryPressure
  case signOutRequested
}

public enum ApplicationLifecycleState: Sendable, Equatable {
  case idle
  case handling(ApplicationLifecycleCommand, generation: UInt64)
  case settled(ApplicationLifecycleCommand, generation: UInt64)
}

public actor ApplicationLifecycleAuthority {
  public private(set) var currentState: ApplicationLifecycleState = .idle

  private let environment: ApplicationEnvironment
  private var generation: UInt64 = 0
  private var nextObserverID: UInt64 = 0
  private var observers: [UInt64: AsyncStream<ApplicationLifecycleState>.Continuation] = [:]

  public init(environment: ApplicationEnvironment) {
    self.environment = environment
  }

  public func states() -> AsyncStream<ApplicationLifecycleState> {
    nextObserverID &+= 1
    let observerID = nextObserverID
    let (stream, continuation) = AsyncStream.makeStream(of: ApplicationLifecycleState.self)
    observers[observerID] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeObserver(observerID) }
    }
    return stream
  }

  public func submit(_ command: ApplicationLifecycleCommand) async {
    generation &+= 1
    let submittedGeneration = generation
    transition(to: .handling(command, generation: submittedGeneration))
    let attemptID = environment.makeAttemptID()

    await perform(command, generation: submittedGeneration)

    guard generation == submittedGeneration else {
      await environment.diagnostics.record(
        RedactedDiagnosticEvent(
          attemptID: attemptID,
          category: .lifecycle,
          outcome: .obsoleteCompletion
        )
      )
      return
    }

    transition(to: .settled(command, generation: submittedGeneration))
  }

  private func transition(to state: ApplicationLifecycleState) {
    currentState = state
    for observer in observers.values {
      observer.yield(state)
    }
  }

  private func removeObserver(_ observerID: UInt64) {
    observers[observerID] = nil
  }

  private func perform(
    _ command: ApplicationLifecycleCommand,
    generation submittedGeneration: UInt64
  ) async {
    switch command {
    case .foregrounded:
      await environment.lifecycle.revalidateSubscription()
    case .backgrounding:
      await environment.lifecycle.checkpointWatchHistory()
      guard generation == submittedGeneration else { return }
      await environment.lifecycle.cancelNonessentialWork()
    case .memoryPressure:
      await environment.lifecycle.releaseVolatileCaches()
    case .signOutRequested:
      await environment.lifecycle.cancelProtectedWork()
      guard generation == submittedGeneration else { return }
      await environment.lifecycle.clearProtectedState()
    }
  }
}
