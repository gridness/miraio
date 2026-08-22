import MiraioApplication
import SwiftUI
import Testing

@testable import Miraio

@Suite("macOS lifecycle composition")
@MainActor
struct AppCompositionTests {
  @Test("the shell translates every platform lifecycle signal into a typed command")
  func translatesLifecycleSignals() async {
    let authority = ApplicationLifecycleAuthority(environment: .testValue)
    let composition = AppComposition(lifecycle: authority)

    await composition.scenePhaseChanged(to: .active)
    #expect(await authority.currentState == .settled(.foregrounded, generation: 1))

    await composition.scenePhaseChanged(to: .background)
    #expect(await authority.currentState == .settled(.backgrounding, generation: 2))

    await composition.receivedMemoryPressure()
    #expect(await authority.currentState == .settled(.memoryPressure, generation: 3))

    await composition.signOutRequested()
    #expect(await authority.currentState == .settled(.signOutRequested, generation: 4))
  }
}

private actor IgnoringDiagnostics: RedactedDiagnostics {
  func record(_ event: RedactedDiagnosticEvent) {}
}

extension ApplicationEnvironment {
  fileprivate static let testValue = ApplicationEnvironment(
    now: { .distantPast },
    makeAttemptID: { .init(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")! },
    diagnostics: IgnoringDiagnostics(),
    lifecycle: LifecycleCapabilities(
      revalidateSubscription: {},
      checkpointWatchHistory: {},
      cancelNonessentialWork: {},
      releaseVolatileCaches: {},
      cancelProtectedWork: {},
      clearProtectedState: {}
    )
  )
}
