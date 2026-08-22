import Foundation
import Testing

@testable import MiraioApplication
import MiraioDomain

@Suite("Demand-driven Catalogue discovery")
struct CatalogueDiscoveryTests {
  @Test("a fresh cached page opens immediately without a timer-driven refresh")
  func freshCacheNeedsNoRefresh() async throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let query = try #require(SeriesQuery(pageSize: 50))
    let page = CataloguePage(
      series: [Series(id: try #require(SeriesID(41)))],
      nextCursor: nil
    )
    let cache = CatalogueCacheFake(
      snapshot: CatalogueSnapshot(page: page, storedAt: now.addingTimeInterval(-30 * 60))
    )
    let remote = CatalogueRemoteFake(page: page)
    let discovery = CatalogueDiscovery(remote: remote, cache: cache, now: { now })

    let stream = await discovery.updates(for: query)
    var updates: [CatalogueUpdate] = []
    for await update in stream {
      updates.append(update)
    }

    #expect(updates == [.snapshot(page, freshness: .fresh, isRefreshing: false)])
    #expect(await remote.pageRequestCount == 0)
  }

  @Test("explicit refresh of a fresh page emits one refreshing snapshot before replacement")
  func explicitRefreshDoesNotReclassifyFreshCacheAsStale() async throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let query = try #require(SeriesQuery(pageSize: 50))
    let cachedPage = CataloguePage(
      series: [Series(id: try #require(SeriesID(41)))],
      nextCursor: nil
    )
    let refreshedPage = CataloguePage(
      series: [Series(id: try #require(SeriesID(42)))],
      nextCursor: nil
    )
    let cache = CatalogueCacheFake(
      snapshot: CatalogueSnapshot(page: cachedPage, storedAt: now.addingTimeInterval(-30 * 60))
    )
    let discovery = CatalogueDiscovery(
      remote: CatalogueRemoteFake(page: refreshedPage),
      cache: cache,
      now: { now }
    )

    let updates = await collect(
      await discovery.updates(for: query, intent: .explicitReload)
    )

    #expect(
      updates == [
        .snapshot(cachedPage, freshness: .fresh, isRefreshing: true),
        .snapshot(refreshedPage, freshness: .fresh, isRefreshing: false),
      ]
    )
  }

  @Test("a one-to-24-hour page stays visible while one bounded refresh runs")
  func staleWhileRefresh() async throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let query = try #require(SeriesQuery(pageSize: 50))
    let cachedPage = CataloguePage(
      series: [Series(id: try #require(SeriesID(41)))],
      nextCursor: nil
    )
    let refreshedPage = CataloguePage(
      series: [Series(id: try #require(SeriesID(42)))],
      nextCursor: nil
    )
    let cache = CatalogueCacheFake(
      snapshot: CatalogueSnapshot(page: cachedPage, storedAt: now.addingTimeInterval(-2 * 60 * 60))
    )
    let remote = CatalogueRemoteFake(page: refreshedPage)
    let discovery = CatalogueDiscovery(remote: remote, cache: cache, now: { now })

    let updates = await collect(await discovery.updates(for: query))
    #expect(
      updates == [
        .snapshot(cachedPage, freshness: .staleWhileRefreshing, isRefreshing: true),
        .snapshot(refreshedPage, freshness: .fresh, isRefreshing: false),
      ]
    )
    #expect(await remote.pageRequestCount == 1)
  }

  @Test("a 24-hour-to-30-day page appears visibly stale only when refresh fails")
  func visiblyStaleFallback() async throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let query = try #require(SeriesQuery(pageSize: 50))
    let cachedPage = CataloguePage(
      series: [Series(id: try #require(SeriesID(41)))],
      nextCursor: nil
    )
    let cache = CatalogueCacheFake(
      snapshot: CatalogueSnapshot(page: cachedPage, storedAt: now.addingTimeInterval(-2 * 24 * 60 * 60))
    )
    let remote = CatalogueRemoteFake(page: cachedPage, failure: .transportUnavailable)
    let discovery = CatalogueDiscovery(
      remote: remote,
      cache: cache,
      now: { now },
      sleep: { _ in },
      retryJitter: { 0 }
    )

    let updates = await collect(await discovery.updates(for: query))

    #expect(
      updates == [
        .staleFallback(
          cachedPage,
          freshness: .visiblyStale,
          failure: .transportUnavailable
        )
      ]
    )
  }

  @Test("a page older than 30 days is unusable even when refresh fails")
  func expiredCacheIsNotAFallback() async throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let query = try #require(SeriesQuery(pageSize: 50))
    let cachedPage = CataloguePage(
      series: [Series(id: try #require(SeriesID(41)))],
      nextCursor: nil
    )
    let cache = CatalogueCacheFake(
      snapshot: CatalogueSnapshot(
        page: cachedPage,
        storedAt: now.addingTimeInterval(-31 * 24 * 60 * 60)
      )
    )
    let discovery = CatalogueDiscovery(
      remote: CatalogueRemoteFake(page: cachedPage, failure: .transportUnavailable),
      cache: cache,
      now: { now },
      sleep: { _ in },
      retryJitter: { 0 }
    )

    let updates = await collect(await discovery.updates(for: query))

    #expect(updates == [.failed(.transportUnavailable, retained: nil)])
  }

  @Test("identical demanded pages share one in-flight request")
  func coalescesIdenticalPageLoads() async throws {
    let query = try #require(SeriesQuery(pageSize: 50))
    let page = CataloguePage(
      series: [Series(id: try #require(SeriesID(41)))],
      nextCursor: nil
    )
    let remote = BlockingCatalogueRemote(page: page)
    let discovery = CatalogueDiscovery(
      remote: remote,
      cache: CatalogueCacheFake(snapshot: nil),
      now: { Date(timeIntervalSince1970: 2_000_000_000) }
    )

    let first = Task { await collect(await discovery.updates(for: query)) }
    await remote.waitUntilRequested()
    let second = Task { await collect(await discovery.updates(for: query)) }
    for _ in 0..<20 { await Task.yield() }

    #expect(await remote.pageRequestCount == 1)
    await remote.resume()
    #expect(await first.value == [.snapshot(page, freshness: .fresh, isRefreshing: false)])
    #expect(await second.value == [.snapshot(page, freshness: .fresh, isRefreshing: false)])
  }

  @Test("distinct Catalogue requests never exceed four concurrent remote operations")
  func boundsConcurrentRemoteOperations() async throws {
    let queries = try (2020...2024).map { year in
      try #require(SeriesQuery(filters: SeriesFilters(year: year), pageSize: 50))
    }
    let remote = ConcurrencyTrackingCatalogueRemote()
    let discovery = CatalogueDiscovery(
      remote: remote,
      cache: CatalogueCacheFake(snapshot: nil)
    )

    let loads = queries.map { query in
      Task { await collect(await discovery.updates(for: query)) }
    }
    await remote.waitUntilRequestCountIsAtLeast(4)
    for _ in 0..<20 { await Task.yield() }

    #expect(await remote.maximumConcurrentRequestCount == 4)
    #expect(await remote.pageRequestCount == 4)

    await remote.resumeAll()
    await remote.waitUntilRequestCountIsAtLeast(5)
    await remote.resumeAll()
    for load in loads { _ = await load.value }
    #expect(await remote.maximumConcurrentRequestCount == 4)
  }

  @Test("a superseded server search cancels during its 300 ms debounce")
  func cancelsSupersededSearchDuringDebounce() async throws {
    let query = try #require(SeriesQuery(searchText: "Frieren", pageSize: 50))
    let page = CataloguePage(series: [], nextCursor: nil)
    let remote = CatalogueRemoteFake(page: page)
    let sleeper = DebounceSleeper()
    let discovery = CatalogueDiscovery(
      remote: remote,
      cache: CatalogueCacheFake(snapshot: nil),
      now: { Date(timeIntervalSince1970: 2_000_000_000) },
      sleep: { try await sleeper.sleep(for: $0) }
    )

    let search = Task { await collect(await discovery.updates(for: query)) }
    await sleeper.waitUntilSleeping()
    search.cancel()

    #expect(await search.value.isEmpty)
    #expect(await sleeper.requestedDurations == [0.3])
    #expect(await remote.pageRequestCount == 0)
  }

  @Test("a transient idempotent failure retries once with bounded jitter")
  func retriesTransientFailureOnce() async throws {
    let query = try #require(SeriesQuery(pageSize: 50))
    let page = CataloguePage(
      series: [Series(id: try #require(SeriesID(41)))],
      nextCursor: nil
    )
    let remote = SequencedCatalogueRemote(results: [
      .failure(.transportUnavailable),
      .success(page),
    ])
    let sleepRecorder = ImmediateSleepRecorder()
    let discovery = CatalogueDiscovery(
      remote: remote,
      cache: CatalogueCacheFake(snapshot: nil),
      now: { Date(timeIntervalSince1970: 2_000_000_000) },
      sleep: { await sleepRecorder.record($0) },
      retryJitter: { 0.2 }
    )

    let updates = await collect(await discovery.updates(for: query))

    #expect(updates == [.snapshot(page, freshness: .fresh, isRefreshing: false)])
    #expect(await remote.pageRequestCount == 2)
    #expect(await sleepRecorder.durations == [0.2])
  }

  @Test("automatic retries cool down while foreground recovery bypasses suppression once")
  func suppressesAutomaticRetryDuringCooldown() async throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let query = try #require(SeriesQuery(pageSize: 50))
    let page = CataloguePage(
      series: [Series(id: try #require(SeriesID(41)))],
      nextCursor: nil
    )
    let remote = SequencedCatalogueRemote(results: [
      .failure(.transportUnavailable),
      .failure(.transportUnavailable),
      .success(page),
    ])
    let discovery = CatalogueDiscovery(
      remote: remote,
      cache: CatalogueCacheFake(snapshot: nil),
      now: { now },
      sleep: { _ in },
      retryJitter: { 0 }
    )

    _ = await collect(await discovery.updates(for: query))
    _ = await collect(await discovery.updates(for: query))
    #expect(await remote.pageRequestCount == 2)

    let recovery = await collect(
      await discovery.updates(for: query, intent: .networkRecovery)
    )
    #expect(recovery == [.snapshot(page, freshness: .fresh, isRefreshing: false)])
    #expect(await remote.pageRequestCount == 3)
  }

  @Test("a partial refresh merges by typed identity without erasing known fields")
  func mergesPartialRefreshByIdentity() async throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let query = try #require(SeriesQuery(pageSize: 50))
    let id = try #require(SeriesID(41))
    let cachedSeries = Series(
      id: id,
      titles: LocalizedSeriesTitles(["en": "Frieren"]),
      typeTitle: "TV Series",
      year: 2023
    )
    let partialSeries = Series(id: id, isAiring: true)
    let cachedPage = CataloguePage(series: [cachedSeries], nextCursor: nil)
    let remotePage = CataloguePage(series: [partialSeries], nextCursor: nil)
    let cache = CatalogueCacheFake(
      snapshot: CatalogueSnapshot(page: cachedPage, storedAt: now.addingTimeInterval(-2 * 60 * 60))
    )
    let discovery = CatalogueDiscovery(
      remote: CatalogueRemoteFake(page: remotePage),
      cache: cache,
      now: { now }
    )

    let updates = await collect(await discovery.updates(for: query))
    let refreshedPage = try #require(updates.last?.page)
    let refreshed = try #require(refreshedPage.series.first)

    #expect(refreshed.title(preferredLanguages: ["en"]) == "Frieren")
    #expect(refreshed.typeTitle == "TV Series")
    #expect(refreshed.year == 2023)
    #expect(refreshed.isAiring == true)
  }

  @Test("backgrounding cancels nonessential Catalogue work without clearing public cache")
  func cancelsNonessentialWork() async throws {
    let query = try #require(SeriesQuery(pageSize: 50))
    let remote = CancellationAwareCatalogueRemote()
    let cache = CatalogueCacheFake(snapshot: nil)
    let discovery = CatalogueDiscovery(remote: remote, cache: cache)

    let loading = Task { await collect(await discovery.updates(for: query)) }
    await remote.waitUntilRequested()
    await discovery.cancelNonessentialWork()

    #expect(await loading.value.isEmpty)
    #expect(await remote.wasCancelled)
    #expect(await cache.clearCount == 0)
  }

  @Test("abandoning the only caller cancels remote Catalogue work after debounce")
  func cancelsAbandonedRemoteWork() async throws {
    let query = try #require(SeriesQuery(pageSize: 50))
    let remote = CancellationAwareCatalogueRemote()
    let discovery = CatalogueDiscovery(
      remote: remote,
      cache: CatalogueCacheFake(snapshot: nil)
    )

    let loading = Task { await collect(await discovery.updates(for: query)) }
    await remote.waitUntilRequested()
    loading.cancel()
    for _ in 0..<30 { await Task.yield() }

    #expect(await remote.wasCancelled)
    await discovery.cancelNonessentialWork()
    _ = await loading.value
  }

  @Test("the Series inspector retains a usable cached detail projection when refresh fails")
  func cachedSeriesDetailsFallback() async throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let id = try #require(SeriesID(41))
    let details = SeriesDetails(
      series: Series(id: id, titles: LocalizedSeriesTitles(["en": "Frieren"])),
      episodes: [],
      translations: []
    )
    let cache = CatalogueCacheFake(
      snapshot: nil,
      detailsSnapshot: CatalogueDetailsSnapshot(
        details: details,
        storedAt: now.addingTimeInterval(-2 * 24 * 60 * 60)
      )
    )
    let discovery = CatalogueDiscovery(
      remote: CatalogueRemoteFake(page: CataloguePage(series: [], nextCursor: nil)),
      cache: cache,
      now: { now }
    )

    let loaded = try await discovery.details(for: id)

    #expect(loaded == details)
  }

  @Test("partial Series details preserve known list and cached relationship fields")
  func mergesPartialSeriesDetails() async throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let seriesID = try #require(SeriesID(41))
    let episodeID = try #require(EpisodeID(4101))
    let translationID = try #require(TranslationID(9001))
    let selectedSeries = Series(
      id: seriesID,
      titles: LocalizedSeriesTitles(["en": "Frieren"]),
      posterURL: URL(string: "https://images.example.test/41.jpg")
    )
    let cachedDetails = SeriesDetails(
      series: Series(id: seriesID, typeTitle: "TV Series"),
      episodes: [
        Episode(
          id: episodeID,
          seriesID: seriesID,
          fullLabel: "Episode 1",
          title: "The Journey's End"
        )
      ],
      translations: [
        Translation(
          id: translationID,
          seriesID: seriesID,
          episodeID: episodeID,
          authors: "AniLibria",
          language: "ru"
        )
      ]
    )
    let refreshedDetails = SeriesDetails(
      series: Series(id: seriesID, year: 2023),
      episodes: [Episode(id: episodeID, seriesID: seriesID, isActive: true)],
      translations: [
        Translation(
          id: translationID,
          seriesID: seriesID,
          episodeID: episodeID,
          quality: "1080p"
        )
      ]
    )
    let cache = CatalogueCacheFake(
      snapshot: nil,
      detailsSnapshot: CatalogueDetailsSnapshot(
        details: cachedDetails,
        storedAt: now.addingTimeInterval(-2 * 60 * 60)
      )
    )
    let discovery = CatalogueDiscovery(
      remote: DetailCatalogueRemote(details: refreshedDetails),
      cache: cache,
      now: { now }
    )

    let loaded = try await discovery.details(for: selectedSeries)

    #expect(loaded.series.title(preferredLanguages: ["en"]) == "Frieren")
    #expect(loaded.series.posterURL == selectedSeries.posterURL)
    #expect(loaded.series.typeTitle == "TV Series")
    #expect(loaded.series.year == 2023)
    #expect(loaded.episodes.first?.fullLabel == "Episode 1")
    #expect(loaded.episodes.first?.title == "The Journey's End")
    #expect(loaded.episodes.first?.isActive == true)
    #expect(loaded.translations.first?.authors == "AniLibria")
    #expect(loaded.translations.first?.language == "ru")
    #expect(loaded.translations.first?.quality == "1080p")
  }
}

private extension CatalogueUpdate {
  var page: CataloguePage? {
    switch self {
    case .snapshot(let page, _, _), .staleFallback(let page, _, _): page
    case .failed(_, let retained): retained
    }
  }
}

private func collect(_ stream: AsyncStream<CatalogueUpdate>) async -> [CatalogueUpdate] {
  var updates: [CatalogueUpdate] = []
  for await update in stream {
    updates.append(update)
  }
  return updates
}

private actor CatalogueRemoteFake: CatalogueRemote {
  private(set) var pageRequestCount = 0
  let page: CataloguePage
  let failure: CatalogueFailure?

  init(page: CataloguePage, failure: CatalogueFailure? = nil) {
    self.page = page
    self.failure = failure
  }

  func loadSeries(query: SeriesQuery, cursor: SeriesCursor?) throws -> CataloguePage {
    pageRequestCount += 1
    if let failure { throw failure }
    return page
  }

  func loadSeriesDetails(id: SeriesID) throws -> SeriesDetails {
    throw CatalogueFailure.notFound
  }
}

private actor DetailCatalogueRemote: CatalogueRemote {
  let details: SeriesDetails

  init(details: SeriesDetails) {
    self.details = details
  }

  func loadSeries(query: SeriesQuery, cursor: SeriesCursor?) -> CataloguePage {
    CataloguePage(series: [], nextCursor: nil)
  }

  func loadSeriesDetails(id: SeriesID) -> SeriesDetails {
    details
  }
}

private actor CatalogueCacheFake: CatalogueCache {
  var snapshot: CatalogueSnapshot?
  var detailsSnapshot: CatalogueDetailsSnapshot?
  private(set) var clearCount = 0

  init(snapshot: CatalogueSnapshot?, detailsSnapshot: CatalogueDetailsSnapshot? = nil) {
    self.snapshot = snapshot
    self.detailsSnapshot = detailsSnapshot
  }

  func snapshot(for request: CataloguePageRequest) -> CatalogueSnapshot? {
    snapshot
  }

  func store(_ snapshot: CatalogueSnapshot, for request: CataloguePageRequest) {
    self.snapshot = snapshot
  }


  func details(for id: SeriesID) -> CatalogueDetailsSnapshot? {
    detailsSnapshot
  }

  func store(_ snapshot: CatalogueDetailsSnapshot, for id: SeriesID) {
    detailsSnapshot = snapshot
  }

  func clear() {
    snapshot = nil
    detailsSnapshot = nil
    clearCount += 1
  }

  func releaseMemory() {}
}

private actor BlockingCatalogueRemote: CatalogueRemote {
  private(set) var pageRequestCount = 0
  private let page: CataloguePage
  private var requestObserver: CheckedContinuation<Void, Never>?
  private var requestContinuations: [CheckedContinuation<Void, Never>] = []

  init(page: CataloguePage) {
    self.page = page
  }

  func loadSeries(query: SeriesQuery, cursor: SeriesCursor?) async -> CataloguePage {
    pageRequestCount += 1
    requestObserver?.resume()
    requestObserver = nil
    await withCheckedContinuation { continuation in
      requestContinuations.append(continuation)
    }
    return page
  }

  func loadSeriesDetails(id: SeriesID) throws -> SeriesDetails {
    throw CatalogueFailure.notFound
  }

  func waitUntilRequested() async {
    guard pageRequestCount == 0 else { return }
    await withCheckedContinuation { continuation in
      requestObserver = continuation
    }
  }

  func resume() {
    let continuations = requestContinuations
    requestContinuations.removeAll()
    for continuation in continuations {
      continuation.resume()
    }
  }
}

private actor ConcurrencyTrackingCatalogueRemote: CatalogueRemote {
  private(set) var pageRequestCount = 0
  private(set) var maximumConcurrentRequestCount = 0
  private var currentRequestCount = 0
  private var requestObservers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
  private var requestContinuations: [CheckedContinuation<Void, Never>] = []

  func loadSeries(query: SeriesQuery, cursor: SeriesCursor?) async -> CataloguePage {
    pageRequestCount += 1
    currentRequestCount += 1
    maximumConcurrentRequestCount = max(maximumConcurrentRequestCount, currentRequestCount)
    resumeSatisfiedObservers()
    await withCheckedContinuation { continuation in
      requestContinuations.append(continuation)
    }
    currentRequestCount -= 1
    return CataloguePage(series: [], nextCursor: nil)
  }

  func loadSeriesDetails(id: SeriesID) throws -> SeriesDetails {
    throw CatalogueFailure.notFound
  }

  func waitUntilRequestCountIsAtLeast(_ count: Int) async {
    guard pageRequestCount < count else { return }
    await withCheckedContinuation { continuation in
      requestObservers.append((count, continuation))
    }
  }

  func resumeAll() {
    let continuations = requestContinuations
    requestContinuations.removeAll()
    for continuation in continuations { continuation.resume() }
  }

  private func resumeSatisfiedObservers() {
    let satisfied = requestObservers.filter { pageRequestCount >= $0.count }
    requestObservers.removeAll { pageRequestCount >= $0.count }
    for observer in satisfied { observer.continuation.resume() }
  }
}

private actor DebounceSleeper {
  private(set) var requestedDurations: [TimeInterval] = []
  private var sleepContinuation: CheckedContinuation<Void, any Error>?
  private var observer: CheckedContinuation<Void, Never>?

  func sleep(for duration: TimeInterval) async throws {
    requestedDurations.append(duration)
    observer?.resume()
    observer = nil
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        sleepContinuation = continuation
      }
    } onCancel: {
      Task { await self.cancelSleep() }
    }
  }

  func waitUntilSleeping() async {
    guard requestedDurations.isEmpty else { return }
    await withCheckedContinuation { continuation in
      observer = continuation
    }
  }

  private func cancelSleep() {
    sleepContinuation?.resume(throwing: CancellationError())
    sleepContinuation = nil
  }
}

private actor SequencedCatalogueRemote: CatalogueRemote {
  private(set) var pageRequestCount = 0
  private var results: [Result<CataloguePage, CatalogueFailure>]

  init(results: [Result<CataloguePage, CatalogueFailure>]) {
    self.results = results
  }

  func loadSeries(query: SeriesQuery, cursor: SeriesCursor?) throws -> CataloguePage {
    pageRequestCount += 1
    return try results.removeFirst().get()
  }

  func loadSeriesDetails(id: SeriesID) throws -> SeriesDetails {
    throw CatalogueFailure.notFound
  }
}

private actor ImmediateSleepRecorder {
  private(set) var durations: [TimeInterval] = []

  func record(_ duration: TimeInterval) {
    durations.append(duration)
  }
}

private actor CancellationAwareCatalogueRemote: CatalogueRemote {
  private(set) var wasCancelled = false
  private var observer: CheckedContinuation<Void, Never>?
  private var didStart = false

  func loadSeries(query: SeriesQuery, cursor: SeriesCursor?) async throws -> CataloguePage {
    didStart = true
    observer?.resume()
    observer = nil
    do {
      try await Task.sleep(for: .seconds(60))
      return CataloguePage(series: [], nextCursor: nil)
    } catch {
      wasCancelled = true
      throw CatalogueFailure.cancelled
    }
  }

  func loadSeriesDetails(id: SeriesID) throws -> SeriesDetails {
    throw CatalogueFailure.notFound
  }

  func waitUntilRequested() async {
    guard !didStart else { return }
    await withCheckedContinuation { continuation in
      observer = continuation
    }
  }
}
