import MiraioApplication
import SwiftUI
import Testing

@testable import Miraio

@Suite("macOS lifecycle composition")
@MainActor
struct AppCompositionTests {
  @Test("the shell translates active and background phases into typed commands")
  func translatesScenePhases() async {
    let authority = ApplicationLifecycleAuthority(environment: .testValue)
    let composition = AppComposition(lifecycle: authority)

    await composition.scenePhaseChanged(to: .active)
    #expect(await authority.currentState == .settled(.foregrounded, generation: 1))

    await composition.scenePhaseChanged(to: .background)
    #expect(await authority.currentState == .settled(.backgrounding, generation: 2))
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
