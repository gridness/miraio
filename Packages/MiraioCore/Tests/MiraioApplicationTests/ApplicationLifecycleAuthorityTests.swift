import Foundation
import Testing

@testable import MiraioApplication

@Suite("Application lifecycle commands")
struct ApplicationLifecycleAuthorityTests {
  @Test("backgrounding checkpoints Watch History before cancelling nonessential work")
  func backgroundingPolicy() async {
    let recorder = CapabilityRecorder()
    let authority = ApplicationLifecycleAuthority(
      environment: .fixture(recordingInto: recorder)
    )

    await authority.submit(.backgrounding)

    #expect(await recorder.values == [.checkpointWatchHistory, .cancelNonessentialWork])
    #expect(await authority.currentState == .settled(.backgrounding, generation: 1))
  }

  @Test("each platform event enters the matching shared behavior")
  func typedCommandPolicy() async {
    let recorder = CapabilityRecorder()
    let authority = ApplicationLifecycleAuthority(
      environment: .fixture(recordingInto: recorder)
    )

    await authority.submit(.foregrounded)
    await authority.submit(.memoryPressure)
    await authority.submit(.signOutRequested)

    #expect(
      await recorder.values == [
        .revalidateSubscription,
        .releaseVolatileCaches,
        .cancelProtectedWork,
        .clearProtectedState,
      ]
    )
  }

  @Test("an obsolete completion cannot replace newer authority state")
  func rejectsObsoleteCompletion() async {
    let gate = AsyncGate()
    let diagnostics = DiagnosticRecorder()
    let environment = ApplicationEnvironment(
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      makeAttemptID: { UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")! },
      diagnostics: diagnostics,
      lifecycle: LifecycleCapabilities(
        revalidateSubscription: { await gate.suspend() },
        checkpointWatchHistory: {},
        cancelNonessentialWork: {},
        releaseVolatileCaches: {},
        cancelProtectedWork: {},
        clearProtectedState: {}
      )
    )
    let authority = ApplicationLifecycleAuthority(environment: environment)

    let obsolete = Task { await authority.submit(.foregrounded) }
    await gate.waitUntilSuspended()
    await authority.submit(.memoryPressure)
    await gate.resume()
    await obsolete.value

    #expect(await authority.currentState == .settled(.memoryPressure, generation: 2))
    #expect(
      await diagnostics.events == [
        RedactedDiagnosticEvent(
          attemptID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
          category: .lifecycle,
          outcome: .obsoleteCompletion
        )
      ]
    )
  }

  @Test("obsolete backgrounding cannot cancel work started after foregrounding")
  func obsoleteBackgroundingStopsBeforeItsSecondEffect() async {
    let gate = AsyncGate()
    let recorder = CapabilityRecorder()
    let environment = ApplicationEnvironment(
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      makeAttemptID: { UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")! },
      diagnostics: DiagnosticRecorder(),
      lifecycle: LifecycleCapabilities(
        revalidateSubscription: { await recorder.append(.revalidateSubscription) },
        checkpointWatchHistory: {
          await recorder.append(.checkpointWatchHistory)
          await gate.suspend()
        },
        cancelNonessentialWork: { await recorder.append(.cancelNonessentialWork) },
        releaseVolatileCaches: {},
        cancelProtectedWork: {},
        clearProtectedState: {}
      )
    )
    let authority = ApplicationLifecycleAuthority(environment: environment)

    let obsolete = Task { await authority.submit(.backgrounding) }
    await gate.waitUntilSuspended()
    await authority.submit(.foregrounded)
    await gate.resume()
    await obsolete.value

    #expect(
      await recorder.values == [
        .checkpointWatchHistory,
        .revalidateSubscription,
      ]
    )
    #expect(await authority.currentState == .settled(.foregrounded, generation: 2))
  }

  @Test("each observer receives a fresh stream of subsequent immutable states")
  func broadcastsStateToEachObserver() async {
    let authority = ApplicationLifecycleAuthority(
      environment: .fixture(recordingInto: CapabilityRecorder())
    )
    let firstStream = await authority.states()
    let secondStream = await authority.states()
    var first = firstStream.makeAsyncIterator()
    var second = secondStream.makeAsyncIterator()

    await authority.submit(.memoryPressure)

    #expect(await first.next() == .handling(.memoryPressure, generation: 1))
    #expect(await first.next() == .settled(.memoryPressure, generation: 1))
    #expect(await second.next() == .handling(.memoryPressure, generation: 1))
    #expect(await second.next() == .settled(.memoryPressure, generation: 1))
  }
}

private enum CapabilityInvocation: Sendable, Equatable {
  case revalidateSubscription
  case checkpointWatchHistory
  case cancelNonessentialWork
  case releaseVolatileCaches
  case cancelProtectedWork
  case clearProtectedState
}

private actor CapabilityRecorder {
  private(set) var values: [CapabilityInvocation] = []

  func append(_ value: CapabilityInvocation) {
    values.append(value)
  }
}

extension ApplicationEnvironment {
  fileprivate static func fixture(recordingInto recorder: CapabilityRecorder) -> Self {
    ApplicationEnvironment(
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      makeAttemptID: { UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")! },
      diagnostics: DiagnosticRecorder(),
      lifecycle: LifecycleCapabilities(
        revalidateSubscription: { await recorder.append(.revalidateSubscription) },
        checkpointWatchHistory: { await recorder.append(.checkpointWatchHistory) },
        cancelNonessentialWork: { await recorder.append(.cancelNonessentialWork) },
        releaseVolatileCaches: { await recorder.append(.releaseVolatileCaches) },
        cancelProtectedWork: { await recorder.append(.cancelProtectedWork) },
        clearProtectedState: { await recorder.append(.clearProtectedState) }
      )
    )
  }
}

private actor DiagnosticRecorder: RedactedDiagnostics {
  private(set) var events: [RedactedDiagnosticEvent] = []

  func record(_ event: RedactedDiagnosticEvent) {
    events.append(event)
  }
}

private actor AsyncGate {
  private var isSuspended = false
  private var suspension: CheckedContinuation<Void, Never>?
  private var observers: [CheckedContinuation<Void, Never>] = []

  func suspend() async {
    isSuspended = true
    let pendingObservers = observers
    observers.removeAll()
    for observer in pendingObservers {
      observer.resume()
    }

    await withCheckedContinuation { continuation in
      suspension = continuation
    }
  }

  func waitUntilSuspended() async {
    guard !isSuspended else { return }
    await withCheckedContinuation { continuation in
      observers.append(continuation)
    }
  }

  func resume() {
    suspension?.resume()
    suspension = nil
  }
}
