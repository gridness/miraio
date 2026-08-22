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
  let authenticationModel: AuthenticationViewModel
  let authentication: AuthenticationAuthority
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
          userAgent: Self.userAgent,
          diagnostics: diagnostics
        )
      }
    #else
      remote = Anime365CatalogueClient(
        userAgent: Self.userAgent,
        diagnostics: diagnostics
      )
    #endif
    let discovery = CatalogueDiscovery(remote: remote, cache: catalogueCache)
    let artwork = ArtworkClient(
      cacheDirectoryURL: cacheRoot.appending(path: "Artwork", directoryHint: .isDirectory)
    )
    let authenticationRemote: any Anime365AuthenticationRemote
    let credentialVault: any AccessTokenVault
    #if DEBUG
      if usesUITestFixture {
        authenticationRemote = UITestAuthenticationRemote()
        credentialVault = UITestAccessTokenVault(
          state: UITestAuthenticationState(
            rawValue: ProcessInfo.processInfo.environment["MIRAIO_UI_AUTH_STATE"] ?? "signed-out"
          ) ?? .signedOut
        )
      } else {
        authenticationRemote = Anime365AuthenticationClient(
          appIdentifier: Self.anime365AppIdentifier,
          userAgent: Self.userAgent
        )
        credentialVault = KeychainAccessTokenVault()
      }
    #else
      authenticationRemote = Anime365AuthenticationClient(
        appIdentifier: Self.anime365AppIdentifier,
        userAgent: Self.userAgent
      )
      credentialVault = KeychainAccessTokenVault()
    #endif
    let authentication = AuthenticationAuthority(
      remote: authenticationRemote,
      credentials: credentialVault,
      protectedSession: EmptyProtectedSession()
    )

    self.artwork = artwork
    self.authentication = authentication
    #if DEBUG
      let fixtureAuthenticationState = usesUITestFixture
        ? uiTestFixtureAuthenticationState
        : nil
    #else
      let fixtureAuthenticationState: AuthenticationState? = nil
    #endif
    authenticationModel = AuthenticationViewModel(
      authority: authentication,
      fixtureState: fixtureAuthenticationState
    )
    catalogueModel = CatalogueViewModel(discovery: discovery)
    self.lifecycle = lifecycle ?? Self.makeLiveLifecycleAuthority(
      discovery: discovery,
      artwork: artwork,
      authentication: authentication,
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
    authentication: AuthenticationAuthority,
    diagnostics: any RedactedDiagnostics
  ) -> ApplicationLifecycleAuthority {
    ApplicationLifecycleAuthority(
      environment: ApplicationEnvironment(
        now: Date.init,
        makeAttemptID: UUID.init,
        diagnostics: diagnostics,
        lifecycle: LifecycleCapabilities(
          revalidateSubscription: { await authentication.foregrounded() },
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
          clearProtectedState: { _ = await authentication.signOut() }
        )
      )
    )
  }

  private static var userAgent: String {
    "Miraio/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development")"
  }

  private static let anime365AppIdentifier = "miraio"
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

  private struct UITestAuthenticationRemote: Anime365AuthenticationRemote {
    func signIn(email: String, password: String) async throws -> AccessToken {
      throw AuthenticationRemoteFailure.rejectedSignIn
    }

    func profile(using token: AccessToken) async throws -> Anime365ProfileVerification {
      throw AuthenticationRemoteFailure.unavailable
    }
  }

  private enum UITestAuthenticationState: String {
    case signedOut = "signed-out"
    case credentialUnavailable = "credential-unavailable"
    case incompleteSignOut = "incomplete-sign-out"
    case verifying
    case inactive
    case subscriber
  }

  private var uiTestFixtureAuthenticationState: AuthenticationState? {
    let value = ProcessInfo.processInfo.environment["MIRAIO_UI_AUTH_STATE"] ?? "signed-out"
    guard let state = UITestAuthenticationState(rawValue: value),
      let profileID = Anime365ProfileID(42)
    else { return nil }
    let profile = Anime365Profile(id: profileID, displayName: "Fixture Profile")
    switch state {
    case .verifying:
      return .verifying
    case .inactive:
      return .authenticatedProfile(profile, eligibility: .inactive)
    case .subscriber:
      return .subscriber(profile)
    case .signedOut, .credentialUnavailable, .incompleteSignOut:
      return nil
    }
  }

  private actor UITestAccessTokenVault: AccessTokenVault {
    private var record: StoredAccessToken?
    private let state: UITestAuthenticationState
    private var latestGeneration: UInt64 = 0

    init(state: UITestAuthenticationState) {
      self.state = state
    }

    func load() throws -> StoredAccessToken? {
      if state == .credentialUnavailable { throw UITestCredentialFailure.unavailable }
      return record
    }
    func storePending(_ token: AccessToken, generation: UInt64) throws {
      try accept(generation)
      record = .pending(token)
    }
    func bind(
      _ token: AccessToken,
      to profileID: Anime365ProfileID,
      generation: UInt64
    ) throws {
      try accept(generation)
      record = .bound(token, profileID: profileID)
    }
    func delete(generation: UInt64) throws {
      try accept(generation)
      record = nil
    }
    func hasIncompleteSignOut() -> Bool { state == .incompleteSignOut }
    func markIncompleteSignOut() {}
    func clearIncompleteSignOut() {}

    private func accept(_ generation: UInt64) throws {
      guard generation >= latestGeneration else {
        throw UITestCredentialFailure.obsoleteMutation
      }
      latestGeneration = generation
    }
  }

  private enum UITestCredentialFailure: Error {
    case unavailable
    case obsoleteMutation
  }
#endif

private actor EmptyProtectedSession: ProtectedSessionClearing {
  func clearProtectedSession() async {}
}

private struct OSLogDiagnostics: RedactedDiagnostics {
  private let logger = Logger(subsystem: "com.gridness.miraio", category: "diagnostics")

  func record(_ event: RedactedDiagnosticEvent) async {
    guard let line = try? event.exportLine() else { return }
    logger.notice("\(line, privacy: .public)")
  }
}
