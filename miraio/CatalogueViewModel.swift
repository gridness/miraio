import Foundation
import MiraioApplication
import MiraioDomain
import Observation

enum MiraioDestination: String, CaseIterable, Identifiable {
  case catalogue
  case search
  case watchHistory

  var id: Self { self }
}

enum CatalogueNotice: Equatable {
  case refreshing
  case visiblyStale
  case partialFailure
  case offline
}

private enum CatalogueCollectionTarget {
  case catalogue
  case search
}

private enum CatalogueUpdateMode {
  case replace
  case append
}

@MainActor
@Observable
final class CatalogueViewModel {
  var destination: MiraioDestination = .catalogue
  var catalogue: [Series] = []
  var catalogueCursor: SeriesCursor?
  var searchText = ""
  var searchResults: [Series] = []
  var searchCursor: SeriesCursor?
  var selectedSeriesID: SeriesID?
  var selectedDetails: SeriesDetails?
  var selectedEpisodeID: EpisodeID?
  var selectedTranslationID: TranslationID?
  var catalogueNotice: CatalogueNotice?
  var searchNotice: CatalogueNotice?
  var isCatalogueLoading = false
  var isSearchLoading = false
  var isInspectorLoading = false

  private let discovery: CatalogueDiscovery
  private var catalogueOperationID: UUID?
  private var searchOperationID: UUID?
  private var inspectorOperation: (id: UUID, task: Task<SeriesDetails, any Error>)?

  init(discovery: CatalogueDiscovery) {
    self.discovery = discovery
  }

  func loadCatalogue(intent: CatalogueLoadIntent = .automatic) async {
    guard let query = SeriesQuery(pageSize: 50) else { return }
    let operationID = UUID()
    catalogueOperationID = operationID
    isCatalogueLoading = true
    defer {
      if catalogueOperationID == operationID { isCatalogueLoading = false }
    }

    let stream = await discovery.updates(for: query, intent: intent)
    for await update in stream {
      guard !Task.isCancelled, catalogueOperationID == operationID else { return }
      apply(update, to: .catalogue, mode: .replace)
    }
  }

  func loadNextCataloguePage() async {
    guard let cursor = catalogueCursor, let query = SeriesQuery(pageSize: 50) else { return }
    let operationID = UUID()
    catalogueOperationID = operationID
    isCatalogueLoading = true
    defer {
      if catalogueOperationID == operationID { isCatalogueLoading = false }
    }

    let stream = await discovery.updates(for: query, cursor: cursor)
    for await update in stream {
      guard !Task.isCancelled, catalogueOperationID == operationID else { return }
      apply(update, to: .catalogue, mode: .append)
    }
  }

  func search() async {
    guard let query = SeriesQuery(searchText: searchText, pageSize: 50),
      query.searchText != nil
    else {
      searchOperationID = nil
      isSearchLoading = false
      searchResults = []
      searchCursor = nil
      searchNotice = nil
      return
    }

    let expectedSearch = query.searchText
    let operationID = UUID()
    searchOperationID = operationID
    isSearchLoading = true
    defer {
      if searchOperationID == operationID { isSearchLoading = false }
    }

    let stream = await discovery.updates(for: query)
    for await update in stream {
      guard !Task.isCancelled,
        searchOperationID == operationID,
        SeriesQuery(searchText: searchText, pageSize: 50)?.searchText == expectedSearch
      else { return }
      apply(update, to: .search, mode: .replace)
    }
  }

  func loadNextSearchPage() async {
    guard let cursor = searchCursor,
      let query = SeriesQuery(searchText: searchText, pageSize: 50),
      query.searchText != nil
    else { return }

    let expectedSearch = query.searchText
    let operationID = UUID()
    searchOperationID = operationID
    isSearchLoading = true
    defer {
      if searchOperationID == operationID { isSearchLoading = false }
    }

    let stream = await discovery.updates(for: query, cursor: cursor)
    for await update in stream {
      guard !Task.isCancelled,
        searchOperationID == operationID,
        SeriesQuery(searchText: searchText, pageSize: 50)?.searchText == expectedSearch
      else { return }
      apply(update, to: .search, mode: .append)
    }
  }

  func select(_ series: Series) async {
    inspectorOperation?.task.cancel()
    selectedSeriesID = series.id
    selectedDetails = nil
    selectedEpisodeID = nil
    selectedTranslationID = nil
    isInspectorLoading = true

    let operationID = UUID()
    let discovery = self.discovery
    let task = Task { try await discovery.details(for: series) }
    inspectorOperation = (operationID, task)
    defer {
      if inspectorOperation?.id == operationID {
        inspectorOperation = nil
        isInspectorLoading = false
      }
    }

    do {
      let details = try await task.value
      guard !Task.isCancelled,
        inspectorOperation?.id == operationID,
        selectedSeriesID == series.id
      else { return }
      selectedDetails = details
      if let episode = details.episodes.first(where: { $0.isActive != false })
        ?? details.episodes.first
      {
        select(episode, in: details)
      }
    } catch {
      guard !Task.isCancelled,
        inspectorOperation?.id == operationID,
        selectedSeriesID == series.id
      else { return }
      selectedDetails = SeriesDetails(series: series, episodes: [], translations: [])
    }
  }

  func select(_ episode: Episode, in details: SeriesDetails? = nil) {
    selectedEpisodeID = episode.id
    let details = details ?? selectedDetails
    selectedTranslationID = details?.translations(for: episode.id)
      .first(where: { $0.isActive != false })?.id
      ?? details?.translations(for: episode.id).first?.id
  }

  func closeInspector() {
    inspectorOperation?.task.cancel()
    inspectorOperation = nil
    isInspectorLoading = false
    selectedSeriesID = nil
    selectedDetails = nil
    selectedEpisodeID = nil
    selectedTranslationID = nil
  }

  func clearCache() async {
    await discovery.clearCache()
    catalogue = []
    catalogueCursor = nil
    searchResults = []
    searchCursor = nil
    await loadCatalogue(intent: .explicitReload)
  }

  private func apply(
    _ update: CatalogueUpdate,
    to target: CatalogueCollectionTarget,
    mode: CatalogueUpdateMode
  ) {
    switch update {
    case .snapshot(let page, let freshness, let isRefreshing):
      set(page: page, to: target, mode: mode)
      let notice: CatalogueNotice? = if isRefreshing {
        .refreshing
      } else if freshness == .visiblyStale {
        .visiblyStale
      } else {
        nil
      }
      set(notice: notice, to: target)
    case .staleFallback(let page, let freshness, let failure):
      set(page: page, to: target, mode: mode)
      let notice: CatalogueNotice = if freshness == .visiblyStale {
        .visiblyStale
      } else if failure == .transportUnavailable {
        .offline
      } else {
        .partialFailure
      }
      set(notice: notice, to: target)
    case .failed(let failure, let retained):
      if let retained { set(page: retained, to: target, mode: mode) }
      set(
        notice: failure == .transportUnavailable ? .offline : .partialFailure,
        to: target
      )
    }
  }

  private func set(
    page: CataloguePage,
    to target: CatalogueCollectionTarget,
    mode: CatalogueUpdateMode
  ) {
    switch target {
    case .search:
      let current = CataloguePage(series: searchResults, nextCursor: searchCursor)
      let result = mode == .append ? current.appending(page) : page
      searchResults = result.series
      searchCursor = result.nextCursor
    case .catalogue:
      let current = CataloguePage(series: catalogue, nextCursor: catalogueCursor)
      let result = mode == .append ? current.appending(page) : page
      catalogue = result.series
      catalogueCursor = result.nextCursor
    }
  }

  private func set(notice: CatalogueNotice?, to target: CatalogueCollectionTarget) {
    switch target {
    case .search:
      searchNotice = notice
    case .catalogue:
      catalogueNotice = notice
    }
  }
}
