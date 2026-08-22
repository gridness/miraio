import Foundation

public struct LocalizedSeriesTitles: Codable, Hashable, Sendable {
  public let values: [String: String]

  public init(_ values: [String: String]) {
    self.values = values.filter { !$0.value.isEmpty }
  }

  public func value(preferredLanguages: [String]) -> String? {
    for preferredLanguage in preferredLanguages {
      let language = preferredLanguage
        .split(separator: "-", maxSplits: 1)
        .first
        .map(String.init)?
        .lowercased()
      if let language, let value = values[language] {
        return value
      }
    }

    return values["en"] ?? values["ru"] ?? values.sorted(by: { $0.key < $1.key }).first?.value
  }
}

public struct Series: Codable, Hashable, Sendable, Identifiable {
  package enum Field: String, Codable, Hashable, Sendable {
    case titles
    case typeTitle
    case posterURL
    case year
    case season
    case isAiring
    case isActive
  }

  public let id: SeriesID
  public let titles: LocalizedSeriesTitles?
  public let typeTitle: String?
  public let posterURL: URL?
  public let year: Int?
  public let season: String?
  public let isAiring: Bool?
  public let isActive: Bool?
  package let providedFields: Set<Field>

  public init(
    id: SeriesID,
    titles: LocalizedSeriesTitles? = nil,
    typeTitle: String? = nil,
    posterURL: URL? = nil,
    year: Int? = nil,
    season: String? = nil,
    isAiring: Bool? = nil,
    isActive: Bool? = nil
  ) {
    self.id = id
    self.titles = titles
    self.typeTitle = typeTitle
    self.posterURL = posterURL
    self.year = year
    self.season = season
    self.isAiring = isAiring
    self.isActive = isActive
    providedFields = Set([
      titles == nil ? nil : .titles,
      typeTitle == nil ? nil : .typeTitle,
      posterURL == nil ? nil : .posterURL,
      year == nil ? nil : .year,
      season == nil ? nil : .season,
      isAiring == nil ? nil : .isAiring,
      isActive == nil ? nil : .isActive,
    ].compactMap(\.self))
  }

  public func title(preferredLanguages: [String] = Locale.preferredLanguages) -> String? {
    titles?.value(preferredLanguages: preferredLanguages)
  }

  package init(
    id: SeriesID,
    titles: LocalizedSeriesTitles?,
    typeTitle: String?,
    posterURL: URL?,
    year: Int?,
    season: String?,
    isAiring: Bool?,
    isActive: Bool?,
    providedFields: Set<Field>
  ) {
    self.id = id
    self.titles = titles
    self.typeTitle = typeTitle
    self.posterURL = posterURL
    self.year = year
    self.season = season
    self.isAiring = isAiring
    self.isActive = isActive
    self.providedFields = providedFields
  }

  package func merging(_ newer: Series) -> Series {
    Series(
      id: id,
      titles: newer.providedFields.contains(.titles) ? newer.titles : titles,
      typeTitle: newer.providedFields.contains(.typeTitle) ? newer.typeTitle : typeTitle,
      posterURL: newer.providedFields.contains(.posterURL) ? newer.posterURL : posterURL,
      year: newer.providedFields.contains(.year) ? newer.year : year,
      season: newer.providedFields.contains(.season) ? newer.season : season,
      isAiring: newer.providedFields.contains(.isAiring) ? newer.isAiring : isAiring,
      isActive: newer.providedFields.contains(.isActive) ? newer.isActive : isActive,
      providedFields: providedFields.union(newer.providedFields)
    )
  }
}

public struct SeriesCursor: Codable, Hashable, Sendable {
  package let query: SeriesQuery
  package let offset: Int

  package init(query: SeriesQuery, offset: Int) {
    self.query = query
    self.offset = offset
  }
}

public struct CataloguePage: Codable, Hashable, Sendable {
  public let series: [Series]
  public let nextCursor: SeriesCursor?

  public init(series: [Series], nextCursor: SeriesCursor?) {
    self.series = series
    self.nextCursor = nextCursor
  }

  package func mergingKnownFields(from older: CataloguePage) -> CataloguePage {
    let olderByID = Dictionary(uniqueKeysWithValues: older.series.map { ($0.id, $0) })
    var seen = Set<SeriesID>()
    var merged = series.map { newer in
      seen.insert(newer.id)
      return olderByID[newer.id]?.merging(newer) ?? newer
    }
    merged.append(contentsOf: older.series.filter { !seen.contains($0.id) })
    return CataloguePage(series: merged, nextCursor: nextCursor)
  }
}

public struct Episode: Codable, Hashable, Sendable, Identifiable {
  public let id: EpisodeID
  public let seriesID: SeriesID
  public let fullLabel: String?
  public let number: Int?
  public let title: String?
  public let type: String?
  public let isActive: Bool?

  public init(
    id: EpisodeID,
    seriesID: SeriesID,
    fullLabel: String? = nil,
    number: Int? = nil,
    title: String? = nil,
    type: String? = nil,
    isActive: Bool? = nil
  ) {
    self.id = id
    self.seriesID = seriesID
    self.fullLabel = fullLabel
    self.number = number
    self.title = title
    self.type = type
    self.isActive = isActive
  }
}

public struct Translation: Codable, Hashable, Sendable, Identifiable {
  public let id: TranslationID
  public let seriesID: SeriesID
  public let episodeID: EpisodeID
  public let authors: String?
  public let type: String?
  public let kind: String?
  public let language: String?
  public let quality: String?
  public let isActive: Bool?

  public init(
    id: TranslationID,
    seriesID: SeriesID,
    episodeID: EpisodeID,
    authors: String? = nil,
    type: String? = nil,
    kind: String? = nil,
    language: String? = nil,
    quality: String? = nil,
    isActive: Bool? = nil
  ) {
    self.id = id
    self.seriesID = seriesID
    self.episodeID = episodeID
    self.authors = authors
    self.type = type
    self.kind = kind
    self.language = language
    self.quality = quality
    self.isActive = isActive
  }
}

public struct SeriesDetails: Codable, Hashable, Sendable {
  public let series: Series
  public let episodes: [Episode]
  public let translations: [Translation]

  public init(series: Series, episodes: [Episode], translations: [Translation]) {
    self.series = series
    self.episodes = episodes
    self.translations = translations
  }

  public func translations(for episodeID: EpisodeID) -> [Translation] {
    translations.filter { $0.episodeID == episodeID }
  }
}
