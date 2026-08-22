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
    let olderByID = Dictionary(older.series.map { ($0.id, $0) }) { first, _ in first }
    let merged = series.map { newer in
      return olderByID[newer.id]?.merging(newer) ?? newer
    }
    return CataloguePage(series: merged, nextCursor: nextCursor)
  }

  public func appending(_ nextPage: CataloguePage) -> CataloguePage {
    var merged = series
    var indices: [SeriesID: Int] = [:]
    for (index, item) in merged.enumerated() where indices[item.id] == nil {
      indices[item.id] = index
    }
    for newer in nextPage.series {
      if let index = indices[newer.id] {
        merged[index] = merged[index].merging(newer)
      } else {
        indices[newer.id] = merged.count
        merged.append(newer)
      }
    }
    return CataloguePage(series: merged, nextCursor: nextPage.nextCursor)
  }
}

public struct Episode: Codable, Hashable, Sendable, Identifiable {
  package enum Field: String, Codable, Hashable, Sendable {
    case fullLabel
    case number
    case title
    case type
    case isActive
  }

  public let id: EpisodeID
  public let seriesID: SeriesID
  public let fullLabel: String?
  public let number: Int?
  public let title: String?
  public let type: String?
  public let isActive: Bool?
  package let providedFields: Set<Field>

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
    providedFields = Set([
      fullLabel == nil ? nil : .fullLabel,
      number == nil ? nil : .number,
      title == nil ? nil : .title,
      type == nil ? nil : .type,
      isActive == nil ? nil : .isActive,
    ].compactMap(\.self))
  }

  package init(
    id: EpisodeID,
    seriesID: SeriesID,
    fullLabel: String?,
    number: Int?,
    title: String?,
    type: String?,
    isActive: Bool?,
    providedFields: Set<Field>
  ) {
    self.id = id
    self.seriesID = seriesID
    self.fullLabel = fullLabel
    self.number = number
    self.title = title
    self.type = type
    self.isActive = isActive
    self.providedFields = providedFields
  }

  package func merging(_ newer: Episode) -> Episode {
    Episode(
      id: id,
      seriesID: seriesID,
      fullLabel: newer.providedFields.contains(.fullLabel) ? newer.fullLabel : fullLabel,
      number: newer.providedFields.contains(.number) ? newer.number : number,
      title: newer.providedFields.contains(.title) ? newer.title : title,
      type: newer.providedFields.contains(.type) ? newer.type : type,
      isActive: newer.providedFields.contains(.isActive) ? newer.isActive : isActive,
      providedFields: providedFields.union(newer.providedFields)
    )
  }
}

public struct Translation: Codable, Hashable, Sendable, Identifiable {
  package enum Field: String, Codable, Hashable, Sendable {
    case authors
    case type
    case kind
    case language
    case quality
    case isActive
  }

  public let id: TranslationID
  public let seriesID: SeriesID
  public let episodeID: EpisodeID
  public let authors: String?
  public let type: String?
  public let kind: String?
  public let language: String?
  public let quality: String?
  public let isActive: Bool?
  package let providedFields: Set<Field>

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
    providedFields = Set([
      authors == nil ? nil : .authors,
      type == nil ? nil : .type,
      kind == nil ? nil : .kind,
      language == nil ? nil : .language,
      quality == nil ? nil : .quality,
      isActive == nil ? nil : .isActive,
    ].compactMap(\.self))
  }

  package init(
    id: TranslationID,
    seriesID: SeriesID,
    episodeID: EpisodeID,
    authors: String?,
    type: String?,
    kind: String?,
    language: String?,
    quality: String?,
    isActive: Bool?,
    providedFields: Set<Field>
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
    self.providedFields = providedFields
  }

  package func merging(_ newer: Translation) -> Translation {
    Translation(
      id: id,
      seriesID: seriesID,
      episodeID: episodeID,
      authors: newer.providedFields.contains(.authors) ? newer.authors : authors,
      type: newer.providedFields.contains(.type) ? newer.type : type,
      kind: newer.providedFields.contains(.kind) ? newer.kind : kind,
      language: newer.providedFields.contains(.language) ? newer.language : language,
      quality: newer.providedFields.contains(.quality) ? newer.quality : quality,
      isActive: newer.providedFields.contains(.isActive) ? newer.isActive : isActive,
      providedFields: providedFields.union(newer.providedFields)
    )
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

  package func mergingKnownFields(
    from older: SeriesDetails?,
    fallbackSeries: Series? = nil
  ) -> SeriesDetails {
    var knownSeries = fallbackSeries
    if let older {
      knownSeries = knownSeries?.merging(older.series) ?? older.series
    }
    let mergedSeries = knownSeries?.merging(series) ?? series
    let olderEpisodes = Dictionary(older?.episodes.map { ($0.id, $0) } ?? []) {
      first, _ in first
    }
    let olderTranslations = Dictionary(older?.translations.map { ($0.id, $0) } ?? []) {
      first, _ in first
    }
    return SeriesDetails(
      series: mergedSeries,
      episodes: episodes.map { olderEpisodes[$0.id]?.merging($0) ?? $0 },
      translations: translations.map { olderTranslations[$0.id]?.merging($0) ?? $0 }
    )
  }
}
