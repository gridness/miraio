import MiraioApplication
import MiraioDomain
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

  @Test("artwork prefetch tracks exactly one viewport beyond visible Series")
  func derivesNextArtworkViewport() throws {
    let series = try (1...10).map { rawValue in
      Series(id: try #require(SeriesID(rawValue)))
    }

    let wideWindow = artworkPrefetchWindow(
      in: series,
      visibleIDs: [series[2].id, series[3].id, series[4].id]
    )
    let inspectorNarrowedWindow = artworkPrefetchWindow(
      in: series,
      visibleIDs: [series[4].id]
    )

    #expect(wideWindow.map(\.id) == [series[5].id, series[6].id, series[7].id])
    #expect(inspectorNarrowedWindow.map(\.id) == [series[5].id])
    #expect(artworkPrefetchWindow(in: series, visibleIDs: []).isEmpty)
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
