import Foundation

public struct SeriesQuery: Codable, Hashable, Sendable {
  public let searchText: String?
  public let filters: SeriesFilters
  public let pageSize: Int

  public init?(
    searchText: String? = nil,
    filters: SeriesFilters = .init(),
    pageSize: Int = 50
  ) {
    guard (1...1_000).contains(pageSize) else { return nil }

    let normalizedSearchText = searchText?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.searchText = normalizedSearchText?.isEmpty == false ? normalizedSearchText : nil
    self.filters = filters
    self.pageSize = pageSize
  }
}

public struct SeriesFilters: Codable, Hashable, Sendable {
  public let isActive: Bool?
  public let isAiring: Bool?
  public let year: Int?
  public let season: SeriesSeason?

  public init(
    isActive: Bool? = true,
    isAiring: Bool? = nil,
    year: Int? = nil,
    season: SeriesSeason? = nil
  ) {
    self.isActive = isActive
    self.isAiring = isAiring
    self.year = year
    self.season = season
  }
}

public enum SeriesSeason: String, Codable, CaseIterable, Sendable {
  case winter
  case spring
  case summer
  case autumn
}
