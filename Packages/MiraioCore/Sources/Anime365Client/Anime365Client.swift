import Foundation
import MiraioApplication
import MiraioDomain

public struct Anime365CatalogueClient: CatalogueRemote, Sendable {
  private let baseURL: URL
  private let userAgent: String
  private let session: URLSession
  private let diagnostics: any RedactedDiagnostics
  private let makeAttemptID: @Sendable () -> UUID

  public init(
    baseURL: URL = URL(string: "https://smotret-anime.app/api/")!,
    userAgent: String,
    session: URLSession? = nil,
    diagnostics: any RedactedDiagnostics,
    makeAttemptID: @escaping @Sendable () -> UUID = UUID.init
  ) {
    self.baseURL = baseURL
    self.userAgent = userAgent
    self.session = session ?? Self.makeEphemeralSession()
    self.diagnostics = diagnostics
    self.makeAttemptID = makeAttemptID
  }

  public func loadSeries(query: SeriesQuery, cursor: SeriesCursor?) async throws -> CataloguePage {
    if let cursor, cursor.query != query {
      throw CatalogueFailure.invalidQuery
    }

    var components = URLComponents(
      url: baseURL.appending(path: "series"),
      resolvingAgainstBaseURL: false
    )
    var queryItems = [
      URLQueryItem(name: "limit", value: String(query.pageSize)),
      URLQueryItem(name: "offset", value: String(cursor?.offset ?? 0)),
      URLQueryItem(
        name: "fields",
        value: "id,titles,typeTitle,posterUrlSmall,year,season,isAiring,isActive"
      ),
    ]
    if let searchText = query.searchText {
      queryItems.append(URLQueryItem(name: "query", value: searchText))
    }
    if let isActive = query.filters.isActive {
      queryItems.append(URLQueryItem(name: "isActive", value: isActive ? "1" : "0"))
    }
    if let isAiring = query.filters.isAiring {
      queryItems.append(URLQueryItem(name: "isAiring", value: isAiring ? "1" : "0"))
    }
    if let year = query.filters.year {
      queryItems.append(URLQueryItem(name: "year", value: String(year)))
    }
    if let season = query.filters.season {
      queryItems.append(URLQueryItem(name: "season", value: season.rawValue))
    }
    components?.queryItems = queryItems

    guard let url = components?.url else {
      throw CatalogueFailure.invalidQuery
    }
    var request = URLRequest(url: url)
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.cachePolicy = .reloadIgnoringLocalCacheData

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch is CancellationError {
      throw CatalogueFailure.cancelled
    } catch {
      throw CatalogueFailure.transportUnavailable
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw CatalogueFailure.unusableResponse
    }
    let envelope: SeriesEnvelope
    do {
      envelope = try JSONDecoder().decode(SeriesEnvelope.self, from: data)
    } catch {
      await record(.unusableResponse)
      throw CatalogueFailure.unusableResponse
    }

    if let providerError = envelope.error {
      throw failure(for: providerError.code, response: httpResponse)
    }
    guard (200..<300).contains(httpResponse.statusCode), let elements = envelope.data else {
      throw failure(for: httpResponse.statusCode, response: httpResponse)
    }

    var series: [Series] = []
    series.reserveCapacity(elements.count)
    for element in elements {
      guard let dto = element.value, let idValue = dto.id, let id = SeriesID(idValue) else {
        await record(.unusableIdentity)
        continue
      }
      series.append(dto.map(id: id))
    }

    let nextCursor = elements.count == query.pageSize
      ? SeriesCursor(query: query, offset: (cursor?.offset ?? 0) + elements.count)
      : nil
    return CataloguePage(series: series, nextCursor: nextCursor)
  }

  public func loadSeriesDetails(id: SeriesID) async throws -> SeriesDetails {
    async let seriesData = request(path: "series/\(id.rawValue)")
    async let episodesData = request(
      path: "episodes",
      queryItems: [
        URLQueryItem(name: "seriesId", value: String(id.rawValue)),
        URLQueryItem(
          name: "fields",
          value: "id,seriesId,episodeFull,episodeInt,episodeTitle,episodeType,isActive"
        ),
      ]
    )
    async let translationsData = request(
      path: "translations",
      queryItems: [
        URLQueryItem(name: "seriesId", value: String(id.rawValue)),
        URLQueryItem(
          name: "fields",
          value: "id,seriesId,episodeId,authorsSummary,type,typeKind,typeLang,qualityType,isActive"
        ),
      ]
    )

    let (rawSeries, rawEpisodes, rawTranslations) = try await (
      seriesData,
      episodesData,
      translationsData
    )
    let seriesEnvelope = try decode(SeriesDetailEnvelope.self, from: rawSeries.data)
    guard let seriesDTO = seriesEnvelope.data?.value, let seriesIDValue = seriesDTO.id,
      let seriesID = SeriesID(seriesIDValue), seriesID == id
    else {
      await record(.unusableIdentity)
      throw CatalogueFailure.unusableResponse
    }
    let series = seriesDTO.map(id: seriesID)

    let episodeEnvelope = try decode(EpisodeEnvelope.self, from: rawEpisodes.data)
    guard let episodeElements = episodeEnvelope.data else {
      throw CatalogueFailure.unusableResponse
    }
    var episodes: [Episode] = []
    for element in episodeElements {
      guard let dto = element.value, let episode = dto.map(expectedSeriesID: id) else {
        await record(.unusableIdentity)
        continue
      }
      episodes.append(episode)
    }

    let translationEnvelope = try decode(TranslationEnvelope.self, from: rawTranslations.data)
    guard let translationElements = translationEnvelope.data else {
      throw CatalogueFailure.unusableResponse
    }
    let usableEpisodeIDs = Set(episodes.map(\.id))
    var translations: [Translation] = []
    for element in translationElements {
      guard let dto = element.value,
        let translation = dto.map(expectedSeriesID: id),
        usableEpisodeIDs.contains(translation.episodeID)
      else {
        await record(.unusableIdentity)
        continue
      }
      translations.append(translation)
    }

    return SeriesDetails(series: series, episodes: episodes, translations: translations)
  }

  private func record(_ outcome: RedactedDiagnosticEvent.Outcome) async {
    await diagnostics.record(
      RedactedDiagnosticEvent(
        attemptID: makeAttemptID(),
        category: .catalogue,
        outcome: outcome
      )
    )
  }

  private func request(
    path: String,
    queryItems: [URLQueryItem] = []
  ) async throws -> (data: Data, response: HTTPURLResponse) {
    var components = URLComponents(
      url: baseURL.appending(path: path),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = queryItems.isEmpty ? nil : queryItems
    guard let url = components?.url else { throw CatalogueFailure.invalidQuery }

    var request = URLRequest(url: url)
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.cachePolicy = .reloadIgnoringLocalCacheData

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch is CancellationError {
      throw CatalogueFailure.cancelled
    } catch {
      throw CatalogueFailure.transportUnavailable
    }
    guard let httpResponse = response as? HTTPURLResponse else {
      throw CatalogueFailure.unusableResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      if let errorEnvelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
        let code = errorEnvelope.error?.code
      {
        throw failure(for: code, response: httpResponse)
      }
      throw failure(for: httpResponse.statusCode, response: httpResponse)
    }
    if let errorEnvelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
      let code = errorEnvelope.error?.code
    {
      throw failure(for: code, response: httpResponse)
    }
    return (data, httpResponse)
  }

  private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw CatalogueFailure.unusableResponse
    }
  }

  private func failure(for code: Int, response: HTTPURLResponse) -> CatalogueFailure {
    if code == 404 { return .notFound }
    if code == 400 || code == 422 { return .invalidQuery }
    if code == 429, let value = response.value(forHTTPHeaderField: "Retry-After"),
      let seconds = TimeInterval(value)
    {
      return .retryAfter(seconds: max(0, seconds))
    }
    return .serviceRejected(code: code)
  }

  package static func makeEphemeralSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieAcceptPolicy = .never
    configuration.httpShouldSetCookies = false
    configuration.httpMaximumConnectionsPerHost = 4
    return URLSession(configuration: configuration)
  }
}

private struct SeriesEnvelope: Decodable {
  let data: [LossyDecodable<SeriesDTO>]?
  let error: ProviderErrorDTO?
}

private struct SeriesDetailEnvelope: Decodable {
  let data: LossyDecodable<SeriesDTO>?
  let error: ProviderErrorDTO?
}

private struct ErrorEnvelope: Decodable {
  let error: ProviderErrorDTO?
}

private struct EpisodeEnvelope: Decodable {
  let data: [LossyDecodable<EpisodeDTO>]?
  let error: ProviderErrorDTO?
}

private struct TranslationEnvelope: Decodable {
  let data: [LossyDecodable<TranslationDTO>]?
  let error: ProviderErrorDTO?
}

private struct ProviderErrorDTO: Decodable {
  let code: Int
}

private struct LossyDecodable<Value: Decodable>: Decodable {
  let value: Value?

  init(from decoder: any Decoder) throws {
    value = try? Value(from: decoder)
  }
}

private struct SeriesDTO: Decodable {
  let id: Int?
  let titles: [String: String]?
  let typeTitle: String?
  let posterURLSmall: URL?
  let year: Int?
  let season: String?
  let isAiring: ProviderBoolean?
  let isActive: ProviderBoolean?
  let providedFields: Set<Series.Field>

  enum CodingKeys: String, CodingKey {
    case id
    case titles
    case typeTitle
    case posterURLSmall = "posterUrlSmall"
    case year
    case season
    case isAiring
    case isActive
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(Int.self, forKey: .id)
    titles = try container.decodeIfPresent([String: String].self, forKey: .titles)
    typeTitle = try container.decodeIfPresent(String.self, forKey: .typeTitle)
    posterURLSmall = try container.decodeIfPresent(URL.self, forKey: .posterURLSmall)
    year = try container.decodeIfPresent(Int.self, forKey: .year)
    season = try container.decodeIfPresent(String.self, forKey: .season)
    isAiring = try container.decodeIfPresent(ProviderBoolean.self, forKey: .isAiring)
    isActive = try container.decodeIfPresent(ProviderBoolean.self, forKey: .isActive)
    providedFields = Set([
      container.contains(.titles) ? .titles : nil,
      container.contains(.typeTitle) ? .typeTitle : nil,
      container.contains(.posterURLSmall) ? .posterURL : nil,
      container.contains(.year) ? .year : nil,
      container.contains(.season) ? .season : nil,
      container.contains(.isAiring) ? .isAiring : nil,
      container.contains(.isActive) ? .isActive : nil,
    ].compactMap(\.self))
  }

  func map(id: SeriesID) -> Series {
    Series(
      id: id,
      titles: titles.map(LocalizedSeriesTitles.init),
      typeTitle: typeTitle,
      posterURL: posterURLSmall,
      year: year,
      season: season,
      isAiring: isAiring?.value,
      isActive: isActive?.value,
      providedFields: providedFields
    )
  }
}

private struct EpisodeDTO: Decodable {
  let id: Int?
  let seriesID: Int?
  let episodeFull: String?
  let episodeInt: Int?
  let episodeTitle: String?
  let episodeType: String?
  let isActive: ProviderBoolean?

  enum CodingKeys: String, CodingKey {
    case id
    case seriesID = "seriesId"
    case episodeFull
    case episodeInt
    case episodeTitle
    case episodeType
    case isActive
  }

  func map(expectedSeriesID: SeriesID) -> Episode? {
    guard let id, let episodeID = EpisodeID(id),
      let seriesID, SeriesID(seriesID) == expectedSeriesID
    else { return nil }
    return Episode(
      id: episodeID,
      seriesID: expectedSeriesID,
      fullLabel: episodeFull,
      number: episodeInt,
      title: episodeTitle,
      type: episodeType,
      isActive: isActive?.value
    )
  }
}

private struct TranslationDTO: Decodable {
  let id: Int?
  let seriesID: Int?
  let episodeID: Int?
  let authorsSummary: String?
  let type: String?
  let typeKind: String?
  let typeLang: String?
  let qualityType: String?
  let isActive: ProviderBoolean?

  enum CodingKeys: String, CodingKey {
    case id
    case seriesID = "seriesId"
    case episodeID = "episodeId"
    case authorsSummary
    case type
    case typeKind
    case typeLang
    case qualityType
    case isActive
  }

  func map(expectedSeriesID: SeriesID) -> Translation? {
    guard let id, let translationID = TranslationID(id),
      let seriesID, SeriesID(seriesID) == expectedSeriesID,
      let episodeID, let mappedEpisodeID = EpisodeID(episodeID)
    else { return nil }
    return Translation(
      id: translationID,
      seriesID: expectedSeriesID,
      episodeID: mappedEpisodeID,
      authors: authorsSummary,
      type: type,
      kind: typeKind,
      language: typeLang,
      quality: qualityType,
      isActive: isActive?.value
    )
  }
}

private struct ProviderBoolean: Decodable {
  let value: Bool

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Bool.self) {
      self.value = value
    } else {
      self.value = try container.decode(Int.self) != 0
    }
  }
}
