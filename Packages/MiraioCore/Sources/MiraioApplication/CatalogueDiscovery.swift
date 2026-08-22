import Foundation
import MiraioDomain

public struct CataloguePageRequest: Codable, Hashable, Sendable {
  public let query: SeriesQuery
  public let cursor: SeriesCursor?

  public init(query: SeriesQuery, cursor: SeriesCursor? = nil) {
    self.query = query
    self.cursor = cursor
  }
}

public struct CatalogueSnapshot: Codable, Hashable, Sendable {
  public let page: CataloguePage
  public let storedAt: Date

  public init(page: CataloguePage, storedAt: Date) {
    self.page = page
    self.storedAt = storedAt
  }
}

public struct CatalogueDetailsSnapshot: Codable, Hashable, Sendable {
  public let details: SeriesDetails
  public let storedAt: Date

  public init(details: SeriesDetails, storedAt: Date) {
    self.details = details
    self.storedAt = storedAt
  }
}

public enum CatalogueFreshness: String, Codable, Hashable, Sendable {
  case fresh
  case staleWhileRefreshing
  case visiblyStale
}

public enum CatalogueUpdate: Equatable, Sendable {
  case snapshot(CataloguePage, freshness: CatalogueFreshness, isRefreshing: Bool)
  case staleFallback(
    CataloguePage,
    freshness: CatalogueFreshness,
    failure: CatalogueFailure
  )
  case failed(CatalogueFailure, retained: CataloguePage?)
}

public enum CatalogueLoadIntent: Equatable, Sendable {
  case automatic
  case explicitReload
  case networkRecovery
}

public protocol CatalogueCache: Sendable {
  func snapshot(for request: CataloguePageRequest) async -> CatalogueSnapshot?
  func store(_ snapshot: CatalogueSnapshot, for request: CataloguePageRequest) async
  func details(for id: SeriesID) async -> CatalogueDetailsSnapshot?
  func store(_ snapshot: CatalogueDetailsSnapshot, for id: SeriesID) async
  func clear() async
  func releaseMemory() async
}

public actor CatalogueDiscovery {
  private struct InFlightPage: Sendable {
    let id: UUID
    let task: Task<CataloguePage, any Error>
    var demandIDs: Set<UUID>
  }
  private struct InFlightDetails: Sendable {
    let id: UUID
    let task: Task<SeriesDetails, any Error>
    var demandIDs: Set<UUID>
  }

  private struct RetrySuppression: Sendable {
    let until: Date
    let failure: CatalogueFailure
  }

  private let remote: any CatalogueRemote
  private let cache: any CatalogueCache
  private let now: @Sendable () -> Date
  private let sleep: @Sendable (TimeInterval) async throws -> Void
  private let retryJitter: @Sendable () -> TimeInterval
  private let remotePermits = AsyncPermitPool(limit: 4)
  private var inFlightPages: [CataloguePageRequest: InFlightPage] = [:]
  private var inFlightDetails: [SeriesID: InFlightDetails] = [:]
  private var retrySuppressions: [CataloguePageRequest: RetrySuppression] = [:]

  public init(
    remote: any CatalogueRemote,
    cache: any CatalogueCache,
    now: @escaping @Sendable () -> Date = Date.init,
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
      try await Task.sleep(for: .seconds(seconds))
    },
    retryJitter: @escaping @Sendable () -> TimeInterval = { Double.random(in: 0.1...0.4) }
  ) {
    self.remote = remote
    self.cache = cache
    self.now = now
    self.sleep = sleep
    self.retryJitter = retryJitter
  }

  public func updates(
    for query: SeriesQuery,
    cursor: SeriesCursor? = nil,
    intent: CatalogueLoadIntent = .automatic
  ) -> AsyncStream<CatalogueUpdate> {
    let request = CataloguePageRequest(query: query, cursor: cursor)
    return AsyncStream { continuation in
      let task = Task {
        await self.produceUpdates(for: request, intent: intent, into: continuation)
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func cancelNonessentialWork() {
    let pageTasks = inFlightPages.values.map(\.task)
    let detailTasks = inFlightDetails.values.map(\.task)
    inFlightPages.removeAll(keepingCapacity: true)
    inFlightDetails.removeAll(keepingCapacity: true)
    for task in pageTasks { task.cancel() }
    for task in detailTasks { task.cancel() }
  }

  public func clearCache() async {
    cancelNonessentialWork()
    retrySuppressions.removeAll(keepingCapacity: false)
    await cache.clear()
  }

  public func releaseVolatileCaches() async {
    await cache.releaseMemory()
  }

  public func details(
    for id: SeriesID,
    intent: CatalogueLoadIntent = .automatic
  ) async throws -> SeriesDetails {
    try await details(for: id, knownSeries: nil, intent: intent)
  }

  public func details(
    for series: Series,
    intent: CatalogueLoadIntent = .automatic
  ) async throws -> SeriesDetails {
    try await details(for: series.id, knownSeries: series, intent: intent)
  }

  private func details(
    for id: SeriesID,
    knownSeries: Series?,
    intent: CatalogueLoadIntent
  ) async throws -> SeriesDetails {
    let cachedSnapshot = await cache.details(for: id)
    let cachedAge = cachedSnapshot.map { max(0, now().timeIntervalSince($0.storedAt)) }
    if intent == .automatic, let cachedSnapshot, let cachedAge, cachedAge <= 60 * 60 {
      return cachedSnapshot.details.mergingKnownFields(
        from: nil,
        fallbackSeries: knownSeries
      )
    }

    do {
      let loadedDetails = try await loadDetails(for: id)
      try Task.checkCancellation()
      let details = loadedDetails.mergingKnownFields(
        from: cachedSnapshot?.details,
        fallbackSeries: knownSeries
      )
      await cache.store(CatalogueDetailsSnapshot(details: details, storedAt: now()), for: id)
      return details
    } catch {
      if let cachedSnapshot, let cachedAge, cachedAge <= 30 * 24 * 60 * 60 {
        return cachedSnapshot.details.mergingKnownFields(
          from: nil,
          fallbackSeries: knownSeries
        )
      }
      throw error
    }
  }

  private func produceUpdates(
    for request: CataloguePageRequest,
    intent: CatalogueLoadIntent,
    into continuation: AsyncStream<CatalogueUpdate>.Continuation
  ) async {
    defer { continuation.finish() }

    let cachedSnapshot = await cache.snapshot(for: request)
    let cachedAge = cachedSnapshot.map { max(0, now().timeIntervalSince($0.storedAt)) }
    if let cachedSnapshot, let cachedAge {
      if cachedAge <= 60 * 60 {
        let isRefreshing = intent != .automatic
        continuation.yield(
          .snapshot(cachedSnapshot.page, freshness: .fresh, isRefreshing: isRefreshing)
        )
        if !isRefreshing { return }
      }
      if cachedAge > 60 * 60, cachedAge <= 24 * 60 * 60 {
        continuation.yield(
          .snapshot(
            cachedSnapshot.page,
            freshness: .staleWhileRefreshing,
            isRefreshing: true
          )
        )
      }
    }

    if intent == .automatic, let suppression = retrySuppressions[request],
      suppression.until > now()
    {
      yieldFailure(
        suppression.failure,
        cachedSnapshot: cachedSnapshot,
        cachedAge: cachedAge,
        into: continuation
      )
      return
    }

    do {
      if request.query.searchText != nil {
        try await sleep(0.3)
      }
      let loadedPage = try await loadPage(for: request)
      guard !Task.isCancelled else { return }
      let page = cachedSnapshot.map { loadedPage.mergingKnownFields(from: $0.page) } ?? loadedPage
      await cache.store(CatalogueSnapshot(page: page, storedAt: now()), for: request)
      retrySuppressions[request] = nil
      continuation.yield(.snapshot(page, freshness: .fresh, isRefreshing: false))
    } catch is CancellationError {
      return
    } catch let failure as CatalogueFailure {
      guard failure != .cancelled else { return }
      if failure.isTransient {
        retrySuppressions[request] = RetrySuppression(
          until: now().addingTimeInterval(5 * 60),
          failure: failure
        )
      }
      yieldFailure(
        failure,
        cachedSnapshot: cachedSnapshot,
        cachedAge: cachedAge,
        into: continuation
      )
    } catch {
      yieldFailure(
        .transportUnavailable,
        cachedSnapshot: cachedSnapshot,
        cachedAge: cachedAge,
        into: continuation
      )
    }
  }

  private func loadPage(for request: CataloguePageRequest) async throws -> CataloguePage {
    let demandID = UUID()
    let inFlight: InFlightPage
    if var existing = inFlightPages[request] {
      existing.demandIDs.insert(demandID)
      inFlightPages[request] = existing
      inFlight = existing
    } else {
      let id = UUID()
      let remote = self.remote
      let remotePermits = self.remotePermits
      let sleep = self.sleep
      let retryJitter = self.retryJitter
      let task = Task {
        do {
          return try await remotePermits.withPermit {
            try await remote.loadSeries(query: request.query, cursor: request.cursor)
          }
        } catch let failure as CatalogueFailure where failure.isTransient {
          let delay = failure.retryDelay ?? retryJitter()
          try await sleep(delay)
          return try await remotePermits.withPermit {
            try await remote.loadSeries(query: request.query, cursor: request.cursor)
          }
        }
      }
      inFlight = InFlightPage(id: id, task: task, demandIDs: [demandID])
      inFlightPages[request] = inFlight
    }

    return try await withTaskCancellationHandler {
      do {
        let page = try await inFlight.task.value
        releasePageDemand(request: request, flightID: inFlight.id, demandID: demandID)
        try Task.checkCancellation()
        return page
      } catch {
        releasePageDemand(request: request, flightID: inFlight.id, demandID: demandID)
        throw error
      }
    } onCancel: {
      Task {
        await self.cancelPageDemand(
          request: request,
          flightID: inFlight.id,
          demandID: demandID
        )
      }
    }
  }

  private func loadDetails(for id: SeriesID) async throws -> SeriesDetails {
    let demandID = UUID()
    let inFlight: InFlightDetails
    if var existing = inFlightDetails[id] {
      existing.demandIDs.insert(demandID)
      inFlightDetails[id] = existing
      inFlight = existing
    } else {
      let token = UUID()
      let remote = self.remote
      let remotePermits = self.remotePermits
      let sleep = self.sleep
      let retryJitter = self.retryJitter
      let task = Task {
        do {
          return try await remotePermits.withPermit {
            try await remote.loadSeriesDetails(id: id)
          }
        } catch let failure as CatalogueFailure where failure.isTransient {
          try await sleep(failure.retryDelay ?? retryJitter())
          return try await remotePermits.withPermit {
            try await remote.loadSeriesDetails(id: id)
          }
        }
      }
      inFlight = InFlightDetails(id: token, task: task, demandIDs: [demandID])
      inFlightDetails[id] = inFlight
    }

    return try await withTaskCancellationHandler {
      do {
        let details = try await inFlight.task.value
        releaseDetailsDemand(seriesID: id, flightID: inFlight.id, demandID: demandID)
        try Task.checkCancellation()
        return details
      } catch {
        releaseDetailsDemand(seriesID: id, flightID: inFlight.id, demandID: demandID)
        throw error
      }
    } onCancel: {
      Task {
        await self.cancelDetailsDemand(
          seriesID: id,
          flightID: inFlight.id,
          demandID: demandID
        )
      }
    }
  }

  private func releasePageDemand(
    request: CataloguePageRequest,
    flightID: UUID,
    demandID: UUID
  ) {
    guard var inFlight = inFlightPages[request], inFlight.id == flightID else { return }
    inFlight.demandIDs.remove(demandID)
    inFlightPages[request] = inFlight.demandIDs.isEmpty ? nil : inFlight
  }

  private func cancelPageDemand(
    request: CataloguePageRequest,
    flightID: UUID,
    demandID: UUID
  ) {
    guard var inFlight = inFlightPages[request], inFlight.id == flightID else { return }
    inFlight.demandIDs.remove(demandID)
    if inFlight.demandIDs.isEmpty {
      inFlightPages[request] = nil
      inFlight.task.cancel()
    } else {
      inFlightPages[request] = inFlight
    }
  }

  private func releaseDetailsDemand(seriesID: SeriesID, flightID: UUID, demandID: UUID) {
    guard var inFlight = inFlightDetails[seriesID], inFlight.id == flightID else { return }
    inFlight.demandIDs.remove(demandID)
    inFlightDetails[seriesID] = inFlight.demandIDs.isEmpty ? nil : inFlight
  }

  private func cancelDetailsDemand(seriesID: SeriesID, flightID: UUID, demandID: UUID) {
    guard var inFlight = inFlightDetails[seriesID], inFlight.id == flightID else { return }
    inFlight.demandIDs.remove(demandID)
    if inFlight.demandIDs.isEmpty {
      inFlightDetails[seriesID] = nil
      inFlight.task.cancel()
    } else {
      inFlightDetails[seriesID] = inFlight
    }
  }

  private func yieldFailure(
    _ failure: CatalogueFailure,
    cachedSnapshot: CatalogueSnapshot?,
    cachedAge: TimeInterval?,
    into continuation: AsyncStream<CatalogueUpdate>.Continuation
  ) {
    if let cachedSnapshot, let cachedAge, cachedAge <= 30 * 24 * 60 * 60 {
      let freshness: CatalogueFreshness
      if cachedAge <= 60 * 60 {
        freshness = .fresh
      } else if cachedAge <= 24 * 60 * 60 {
        freshness = .staleWhileRefreshing
      } else {
        freshness = .visiblyStale
      }
      continuation.yield(
        .staleFallback(cachedSnapshot.page, freshness: freshness, failure: failure)
      )
    } else {
      continuation.yield(.failed(failure, retained: nil))
    }
  }
}

private extension CatalogueFailure {
  var isTransient: Bool {
    switch self {
    case .transportUnavailable, .retryAfter:
      true
    case .serviceRejected(let code):
      (500...599).contains(code)
    case .cancelled, .notFound, .invalidQuery, .unusableResponse:
      false
    }
  }

  var retryDelay: TimeInterval? {
    guard case .retryAfter(let seconds) = self else { return nil }
    return seconds
  }
}
