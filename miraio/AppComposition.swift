import Anime365Client
import Foundation
import MiraioASSRenderer
import MiraioApplication
import MiraioArtwork
import MiraioCredentials
import MiraioDomain
import MiraioPlayback
import MiraioWatchHistory
import OSLog
import SwiftUI

@MainActor
final class AppComposition {
  let lifecycle: ApplicationLifecycleAuthority

  init(lifecycle: ApplicationLifecycleAuthority? = nil) {
    self.lifecycle = lifecycle ?? Self.makeLiveLifecycleAuthority()
  }

  func scenePhaseChanged(to scenePhase: ScenePhase) async {
    switch scenePhase {
    case .active:
      await lifecycle.submit(.foregrounded)
    case .background:
      await lifecycle.submit(.backgrounding)
    case .inactive:
      break
    @unknown default:
      break
    }
  }

  func receivedMemoryPressure() async {
    await lifecycle.submit(.memoryPressure)
  }

  func signOutRequested() async {
    await lifecycle.submit(.signOutRequested)
  }

  private static func makeLiveLifecycleAuthority() -> ApplicationLifecycleAuthority {
    ApplicationLifecycleAuthority(
      environment: ApplicationEnvironment(
        now: Date.init,
        makeAttemptID: UUID.init,
        diagnostics: OSLogDiagnostics(),
        lifecycle: LifecycleCapabilities(
          revalidateSubscription: {},
          checkpointWatchHistory: {},
          cancelNonessentialWork: {},
          releaseVolatileCaches: {},
          cancelProtectedWork: {},
          clearProtectedState: {}
        )
      )
    )
  }
}

private struct OSLogDiagnostics: RedactedDiagnostics {
  private let logger = Logger(subsystem: "com.gridness.miraio", category: "diagnostics")

  func record(_ event: RedactedDiagnosticEvent) async {
    guard let line = try? event.exportLine() else { return }
    logger.notice("\(line, privacy: .public)")
  }
}
