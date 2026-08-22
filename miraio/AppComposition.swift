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
  let catalogueModel: CatalogueViewModel
  let artwork: any ArtworkLoading

  init(lifecycle: ApplicationLifecycleAuthority? = nil) {
    let diagnostics = OSLogDiagnostics()
    let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
      .first!
      .appending(path: "Miraio", directoryHint: .isDirectory)
    let catalogueCache = BoundedCatalogueCache(
      directoryURL: cacheRoot.appending(path: "Catalogue", directoryHint: .isDirectory)
    )
    let remote = Anime365CatalogueClient(
      userAgent: "Miraio/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development")",
      diagnostics: diagnostics
    )
    let discovery = CatalogueDiscovery(remote: remote, cache: catalogueCache)
    let artwork = ArtworkClient(
      cacheDirectoryURL: cacheRoot.appending(path: "Artwork", directoryHint: .isDirectory)
    )

    self.artwork = artwork
    catalogueModel = CatalogueViewModel(discovery: discovery)
    self.lifecycle = lifecycle ?? Self.makeLiveLifecycleAuthority(
      discovery: discovery,
      artwork: artwork,
      diagnostics: diagnostics
    )
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

  private static func makeLiveLifecycleAuthority(
    discovery: CatalogueDiscovery,
    artwork: any ArtworkLoading,
    diagnostics: any RedactedDiagnostics
  ) -> ApplicationLifecycleAuthority {
    ApplicationLifecycleAuthority(
      environment: ApplicationEnvironment(
        now: Date.init,
        makeAttemptID: UUID.init,
        diagnostics: diagnostics,
        lifecycle: LifecycleCapabilities(
          revalidateSubscription: {},
          checkpointWatchHistory: {},
          cancelNonessentialWork: {
            await discovery.cancelNonessentialWork()
            await artwork.cancelNonessentialWork()
          },
          releaseVolatileCaches: {
            await discovery.releaseVolatileCaches()
            await artwork.releaseDecodedImages()
          },
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
