import Foundation
import Testing

import Anime365Client
import MiraioApplication
import MiraioDomain

@Suite("Official Anime365 Catalogue mapping", .serialized)
struct Anime365CatalogueClientTests {
  @Test("Catalogue transport is ephemeral, cookieless, uncached, and connection-bounded")
  func usesPublicCatalogueNetworkPurpose() {
    let configuration = Anime365CatalogueClient.makeEphemeralSession().configuration

    #expect(configuration.urlCache == nil)
    #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    #expect(configuration.httpCookieAcceptPolicy == .never)
    #expect(configuration.httpShouldSetCookies == false)
    #expect(configuration.httpMaximumConnectionsPerHost == 4)
  }

  @Test("malformed identities are skipped while valid siblings and documented fields survive")
  func mapsPartialSeriesEnvelope() async throws {
    let diagnostics = CatalogueDiagnosticRecorder()
    let client = Anime365CatalogueClient(
      baseURL: try #require(URL(string: "https://example.test/api/")),
      userAgent: "MiraioTests/1",
      session: makeStubbedSession(
        statusCode: 200,
        body: #"""
          {
            "data": [
              {
                "id": 41,
                "titles": {"en": "Frieren", "ru": "Фрирен"},
                "typeTitle": "TV Series",
                "posterUrlSmall": "https://images.example.test/41.jpg",
                "year": 2023,
                "futureField": {"ignored": true}
              },
              {"id": "broken", "titles": {"en": "Malformed"}},
              {"id": 42, "titles": null, "isAiring": 1},
              {"titles": {"en": "Missing identity"}}
            ]
          }
          """#
      ),
      diagnostics: diagnostics
    )
    let query = try #require(SeriesQuery(searchText: "Frieren", pageSize: 4))

    let page = try await client.loadSeries(query: query, cursor: nil)

    #expect(page.series.map(\.id) == [SeriesID(41), SeriesID(42)])
    #expect(page.series[0].title(preferredLanguages: ["ru"]) == "Фрирен")
    #expect(page.series[0].typeTitle == "TV Series")
    #expect(page.series[0].posterURL == URL(string: "https://images.example.test/41.jpg"))
    #expect(page.series[0].year == 2023)
    #expect(page.series[1].isAiring == true)
    #expect(page.nextCursor != nil)
    #expect(await diagnostics.events.count == 2)

    let request = try #require(URLProtocolStub.lastRequest)
    let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
    #expect(components.path == "/api/series")
    #expect(components.queryItems?.contains(URLQueryItem(name: "query", value: "Frieren")) == true)
    #expect(components.queryItems?.contains(URLQueryItem(name: "isActive", value: "1")) == true)
    #expect(components.queryItems?.contains(URLQueryItem(name: "limit", value: "4")) == true)
  }

  @Test("Series details use only flat documented Episode and Translation relationships")
  func mapsFlatSeriesDetails() async throws {
    let requestedPaths = RequestedPathRecorder()
    let client = Anime365CatalogueClient(
      baseURL: try #require(URL(string: "https://example.test/api/")),
      userAgent: "MiraioTests/1",
      session: makeStubbedSession { request in
        let url = try #require(request.url)
        requestedPaths.record(url.path)
        let body = switch url.path {
        case "/api/series/41":
          #"{"data":{"id":41,"titles":{"en":"Frieren"}}}"#
        case "/api/episodes":
          #"{"data":[{"id":4101,"seriesId":41,"episodeFull":"Episode 1","episodeInt":1,"episodeTitle":"The Journey's End","episodeType":"tv","isActive":1},{"id":4102,"seriesId":"broken"}]}"#
        case "/api/translations":
          #"{"data":[{"id":9001,"seriesId":41,"episodeId":4101,"authorsSummary":"AniLibria","type":"dub","typeKind":"voice","typeLang":"ru","qualityType":"1080p","isActive":1},{"id":9002,"seriesId":99,"episodeId":4101}]}"#
        default:
          #"{"error":{"code":404,"message":"missing"}}"#
        }
        return (200, body)
      },
      diagnostics: CatalogueDiagnosticRecorder()
    )

    let details = try await client.loadSeriesDetails(id: try #require(SeriesID(41)))

    #expect(details.series.title(preferredLanguages: ["en"]) == "Frieren")
    #expect(details.episodes.map(\.id) == [EpisodeID(4101)])
    #expect(details.episodes[0].number == 1)
    #expect(details.translations.map(\.id) == [TranslationID(9001)])
    #expect(details.translations[0].episodeID == EpisodeID(4101))
    #expect(Set(requestedPaths.values) == ["/api/series/41", "/api/episodes", "/api/translations"])
  }
}

@Suite("Bounded public Catalogue cache")
struct BoundedCatalogueCacheTests {
  @Test("a successful projection survives memory release and Clear Cache removes only it")
  func persistsAndClearsProjection() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let query = try #require(SeriesQuery(pageSize: 50))
    let request = CataloguePageRequest(query: query)
    let page = CataloguePage(
      series: [Series(id: try #require(SeriesID(41)))],
      nextCursor: nil
    )
    let snapshot = CatalogueSnapshot(
      page: page,
      storedAt: Date(timeIntervalSince1970: 2_000_000_000)
    )
    let cache = BoundedCatalogueCache(directoryURL: directory)

    await cache.store(snapshot, for: request)
    await cache.releaseMemory()
    let reopened = BoundedCatalogueCache(directoryURL: directory)

    #expect(await reopened.snapshot(for: request) == snapshot)
    await reopened.clear()
    #expect(await reopened.snapshot(for: request) == nil)
  }

  @Test("the configured disk budget evicts the least-recently-used projection")
  func evictsLeastRecentlyUsedProjection() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let firstRequest = CataloguePageRequest(
      query: try #require(SeriesQuery(filters: SeriesFilters(year: 2023)))
    )
    let secondRequest = CataloguePageRequest(
      query: try #require(SeriesQuery(filters: SeriesFilters(year: 2024)))
    )
    let largeTitle = String(repeating: "a", count: 1_200)
    let first = CatalogueSnapshot(
      page: CataloguePage(
        series: [
          Series(
            id: try #require(SeriesID(41)),
            titles: LocalizedSeriesTitles(["en": largeTitle])
          )
        ],
        nextCursor: nil
      ),
      storedAt: Date(timeIntervalSince1970: 2_000_000_000)
    )
    let second = CatalogueSnapshot(
      page: CataloguePage(
        series: [
          Series(
            id: try #require(SeriesID(42)),
            titles: LocalizedSeriesTitles(["en": largeTitle])
          )
        ],
        nextCursor: nil
      ),
      storedAt: Date(timeIntervalSince1970: 2_000_000_001)
    )
    let cache = BoundedCatalogueCache(
      directoryURL: directory,
      memoryCapacity: 1,
      diskCapacity: 2_200
    )

    await cache.store(first, for: firstRequest)
    try await Task.sleep(for: .milliseconds(20))
    await cache.store(second, for: secondRequest)
    await cache.releaseMemory()

    #expect(await cache.snapshot(for: firstRequest) == nil)
    #expect(await cache.snapshot(for: secondRequest) == second)
  }
}

private actor CatalogueDiagnosticRecorder: RedactedDiagnostics {
  private(set) var events: [RedactedDiagnosticEvent] = []

  func record(_ event: RedactedDiagnosticEvent) {
    events.append(event)
  }
}

private func makeStubbedSession(statusCode: Int, body: String) -> URLSession {
  makeStubbedSession { _ in (statusCode, body) }
}

private func makeStubbedSession(
  handler: @escaping @Sendable (URLRequest) throws -> (statusCode: Int, body: String)
) -> URLSession {
  URLProtocolStub.handler = handler
  URLProtocolStub.lastRequest = nil
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [URLProtocolStub.self]
  return URLSession(configuration: configuration)
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, String))!
  nonisolated(unsafe) static var lastRequest: URLRequest?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lastRequest = request
    do {
      let result = try Self.handler(request)
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: result.0,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(result.1.utf8))
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

private final class RequestedPathRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String] = []

  var values: [String] {
    lock.withLock { storage }
  }

  func record(_ path: String) {
    lock.withLock { storage.append(path) }
  }
}
