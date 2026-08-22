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
    let usesUITestFixture = ProcessInfo.processInfo.environment["MIRAIO_UI_FIXTURE"] == "1"
    let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
      .first!
      .appending(
        path: usesUITestFixture ? "Miraio-UITestFixture" : "Miraio",
        directoryHint: .isDirectory
      )
    let catalogueCache = BoundedCatalogueCache(
      directoryURL: cacheRoot.appending(path: "Catalogue", directoryHint: .isDirectory)
    )
    let remote: any CatalogueRemote
    #if DEBUG
      if usesUITestFixture {
        remote = UITestCatalogueRemote()
      } else {
        remote = Anime365CatalogueClient(
          userAgent: "Miraio/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development")",
          diagnostics: diagnostics
        )
      }
    #else
      remote = Anime365CatalogueClient(
        userAgent: "Miraio/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development")",
        diagnostics: diagnostics
      )
    #endif
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

#if DEBUG
  private actor UITestCatalogueRemote: CatalogueRemote {
    func loadSeries(query: SeriesQuery, cursor: SeriesCursor?) throws -> CataloguePage {
      CataloguePage(
        series: [
          Series(
            id: SeriesID(41)!,
            titles: LocalizedSeriesTitles([
              "en": "Frieren: Beyond Journey's End",
              "ru": "Провожающая в последний путь Фрирен",
            ]),
            typeTitle: "TV Series",
            year: 2023,
            season: "Autumn 2023",
            isAiring: false,
            isActive: true
          ),
          Series(
            id: SeriesID(42)!,
            titles: LocalizedSeriesTitles([
              "en": "The Apothecary Diaries",
              "ru": "Монолог фармацевта",
            ]),
            typeTitle: "TV Series",
            year: 2023,
            isActive: true
          ),
        ],
        nextCursor: nil
      )
    }

    func loadSeriesDetails(id: SeriesID) throws -> SeriesDetails {
      let series = Series(
        id: id,
        titles: LocalizedSeriesTitles([
          "en": id == SeriesID(41) ? "Frieren: Beyond Journey's End" : "The Apothecary Diaries",
          "ru": id == SeriesID(41) ? "Провожающая в последний путь Фрирен" : "Монолог фармацевта",
        ]),
        typeTitle: "TV Series",
        year: 2023,
        isActive: true
      )
      let episodeID = EpisodeID(id.rawValue * 100 + 1)!
      return SeriesDetails(
        series: series,
        episodes: [
          Episode(
            id: episodeID,
            seriesID: id,
            fullLabel: "Episode 1",
            number: 1,
            title: "The Journey's End",
            type: "tv",
            isActive: true
          )
        ],
        translations: [
          MiraioDomain.Translation(
            id: TranslationID(id.rawValue * 1000 + 1)!,
            seriesID: id,
            episodeID: episodeID,
            authors: "AniLibria",
            type: "dub",
            kind: "voice",
            language: "ru",
            quality: "1080p",
            isActive: true
          )
        ]
      )
    }
  }
#endif

private struct OSLogDiagnostics: RedactedDiagnostics {
  private let logger = Logger(subsystem: "com.gridness.miraio", category: "diagnostics")

  func record(_ event: RedactedDiagnosticEvent) async {
    guard let line = try? event.exportLine() else { return }
    logger.notice("\(line, privacy: .public)")
  }
}
