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

  init(discovery: CatalogueDiscovery) {
    self.discovery = discovery
  }

  func loadCatalogue(intent: CatalogueLoadIntent = .automatic) async {
    guard let query = SeriesQuery(pageSize: 50) else { return }
    isCatalogueLoading = true
    defer { isCatalogueLoading = false }

    let stream = await discovery.updates(for: query, intent: intent)
    for await update in stream {
      guard !Task.isCancelled else { return }
      apply(update, toSearch: false, appending: false)
    }
  }

  func loadNextCataloguePage() async {
    guard let cursor = catalogueCursor, let query = SeriesQuery(pageSize: 50) else { return }
    isCatalogueLoading = true
    defer { isCatalogueLoading = false }
    let stream = await discovery.updates(for: query, cursor: cursor)
    for await update in stream {
      guard !Task.isCancelled else { return }
      apply(update, toSearch: false, appending: true)
    }
  }

  func search() async {
    guard let query = SeriesQuery(searchText: searchText, pageSize: 50),
      query.searchText != nil
    else {
      searchResults = []
      searchCursor = nil
      searchNotice = nil
      return
    }
    let expectedSearch = query.searchText
    isSearchLoading = true
    defer { isSearchLoading = false }
    let stream = await discovery.updates(for: query)
    for await update in stream {
      guard !Task.isCancelled,
        SeriesQuery(searchText: searchText, pageSize: 50)?.searchText == expectedSearch
      else { return }
      apply(update, toSearch: true, appending: false)
    }
  }

  func loadNextSearchPage() async {
    guard let cursor = searchCursor,
      let query = SeriesQuery(searchText: searchText, pageSize: 50),
      query.searchText != nil
    else { return }
    isSearchLoading = true
    defer { isSearchLoading = false }
    let stream = await discovery.updates(for: query, cursor: cursor)
    for await update in stream {
      guard !Task.isCancelled else { return }
      apply(update, toSearch: true, appending: true)
    }
  }

  func select(_ series: Series) async {
    selectedSeriesID = series.id
    selectedDetails = nil
    selectedEpisodeID = nil
    selectedTranslationID = nil
    isInspectorLoading = true
    defer { isInspectorLoading = false }
    do {
      let details = try await discovery.details(for: series.id)
      guard !Task.isCancelled, selectedSeriesID == series.id else { return }
      selectedDetails = details
      if let episode = details.episodes.first(where: { $0.isActive != false })
        ?? details.episodes.first
      {
        select(episode, in: details)
      }
    } catch {
      guard !Task.isCancelled else { return }
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
    toSearch: Bool,
    appending: Bool
  ) {
    switch update {
    case .snapshot(let page, let freshness, let isRefreshing):
      set(page: page, toSearch: toSearch, appending: appending)
      let notice: CatalogueNotice? = if isRefreshing {
        .refreshing
      } else if freshness == .visiblyStale {
        .visiblyStale
      } else {
        nil
      }
      set(notice: notice, toSearch: toSearch)
    case .staleFallback(let page, let failure):
      set(page: page, toSearch: toSearch, appending: appending)
      set(notice: failure == .transportUnavailable ? .offline : .visiblyStale, toSearch: toSearch)
    case .failed(let failure, let retained):
      if let retained { set(page: retained, toSearch: toSearch, appending: appending) }
      set(notice: failure == .transportUnavailable ? .offline : .partialFailure, toSearch: toSearch)
    }
  }

  private func set(page: CataloguePage, toSearch: Bool, appending: Bool) {
    if toSearch {
      searchResults = appending ? merge(searchResults, with: page.series) : page.series
      searchCursor = page.nextCursor
    } else {
      catalogue = appending ? merge(catalogue, with: page.series) : page.series
      catalogueCursor = page.nextCursor
    }
  }

  private func set(notice: CatalogueNotice?, toSearch: Bool) {
    if toSearch { searchNotice = notice } else { catalogueNotice = notice }
  }

  private func merge(_ existing: [Series], with incoming: [Series]) -> [Series] {
    var result = existing
    var indices = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($0.element.id, $0.offset) })
    for series in incoming {
      if let index = indices[series.id] {
        result[index] = series
      } else {
        indices[series.id] = result.count
        result.append(series)
      }
    }
    return result
  }
}
