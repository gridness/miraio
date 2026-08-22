import Foundation
import MiraioApplication
import MiraioDomain

public struct Anime365CatalogueClient: CatalogueRemote, Sendable {
  private let baseURL: URL
  private let userAgent: String
  private let session: URLSession
  private let diagnostics: any RedactedDiagnostics
  private let makeAttemptID: @Sendable () -> UUID
  private let now: @Sendable () -> Date

  public init(
    baseURL: URL = URL(string: "https://smotret-anime.app/api/")!,
    userAgent: String,
    session: URLSession? = nil,
    diagnostics: any RedactedDiagnostics,
    makeAttemptID: @escaping @Sendable () -> UUID = UUID.init,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.baseURL = baseURL
    self.userAgent = userAgent
    self.session = session ?? Self.makeEphemeralSession()
    self.diagnostics = diagnostics
    self.makeAttemptID = makeAttemptID
    self.now = now
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
    var indices: [SeriesID: Int] = [:]
    series.reserveCapacity(elements.count)
    for element in elements {
      guard let dto = element.value, let idValue = dto.id, let id = SeriesID(idValue) else {
        await record(.unusableIdentity)
        continue
      }
      let mapped = dto.map(id: id)
      if let index = indices[id] {
        series[index] = series[index].merging(mapped)
      } else {
        indices[id] = series.count
        series.append(mapped)
      }
    }
    guard elements.isEmpty || !series.isEmpty else {
      throw CatalogueFailure.unusableResponse
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
    guard episodeElements.isEmpty || !episodes.isEmpty else {
      throw CatalogueFailure.unusableResponse
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
    guard translationElements.isEmpty || !translations.isEmpty else {
      throw CatalogueFailure.unusableResponse
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
    if let value = response.value(forHTTPHeaderField: "Retry-After"),
      let delay = retryAfterDelay(value)
    {
      return .retryAfter(seconds: delay)
    }
    if code == 429 { return .retryAfter(seconds: 0) }
    return .serviceRejected(code: code)
  }

  private func retryAfterDelay(_ value: String) -> TimeInterval? {
    if let seconds = TimeInterval(value) { return max(0, seconds) }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    for format in [
      "EEE',' dd MMM yyyy HH':'mm':'ss zzz",
      "EEEE',' dd-MMM-yy HH':'mm':'ss zzz",
      "EEE MMM d HH':'mm':'ss yyyy",
    ] {
      formatter.dateFormat = format
      if let date = formatter.date(from: value) {
        return max(0, date.timeIntervalSince(now()))
      }
    }
    return nil
  }

  package static func makeEphemeralSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieAcceptPolicy = .never
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
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
    id = container.tolerantValue(Int.self, forKey: .id).value
    let titlesField = container.tolerantValue([String: String].self, forKey: .titles)
    let typeTitleField = container.tolerantValue(String.self, forKey: .typeTitle)
    let posterURLField = container.tolerantValue(URL.self, forKey: .posterURLSmall)
    let yearField = container.tolerantValue(Int.self, forKey: .year)
    let seasonField = container.tolerantValue(String.self, forKey: .season)
    let isAiringField = container.tolerantValue(ProviderBoolean.self, forKey: .isAiring)
    let isActiveField = container.tolerantValue(ProviderBoolean.self, forKey: .isActive)
    titles = titlesField.value
    typeTitle = typeTitleField.value
    posterURLSmall = posterURLField.value
    year = yearField.value
    season = seasonField.value
    isAiring = isAiringField.value
    isActive = isActiveField.value
    providedFields = Set([
      titlesField.isProvided ? .titles : nil,
      typeTitleField.isProvided ? .typeTitle : nil,
      posterURLField.isProvided ? .posterURL : nil,
      yearField.isProvided ? .year : nil,
      seasonField.isProvided ? .season : nil,
      isAiringField.isProvided ? .isAiring : nil,
      isActiveField.isProvided ? .isActive : nil,
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
  let providedFields: Set<Episode.Field>

  enum CodingKeys: String, CodingKey {
    case id
    case seriesID = "seriesId"
    case episodeFull
    case episodeInt
    case episodeTitle
    case episodeType
    case isActive
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = container.tolerantValue(Int.self, forKey: .id).value
    seriesID = container.tolerantValue(Int.self, forKey: .seriesID).value
    let fullLabelField = container.tolerantValue(String.self, forKey: .episodeFull)
    let numberField = container.tolerantValue(Int.self, forKey: .episodeInt)
    let titleField = container.tolerantValue(String.self, forKey: .episodeTitle)
    let typeField = container.tolerantValue(String.self, forKey: .episodeType)
    let isActiveField = container.tolerantValue(ProviderBoolean.self, forKey: .isActive)
    episodeFull = fullLabelField.value
    episodeInt = numberField.value
    episodeTitle = titleField.value
    episodeType = typeField.value
    isActive = isActiveField.value
    providedFields = Set([
      fullLabelField.isProvided ? .fullLabel : nil,
      numberField.isProvided ? .number : nil,
      titleField.isProvided ? .title : nil,
      typeField.isProvided ? .type : nil,
      isActiveField.isProvided ? .isActive : nil,
    ].compactMap(\.self))
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
      isActive: isActive?.value,
      providedFields: providedFields
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
  let providedFields: Set<Translation.Field>

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

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = container.tolerantValue(Int.self, forKey: .id).value
    seriesID = container.tolerantValue(Int.self, forKey: .seriesID).value
    episodeID = container.tolerantValue(Int.self, forKey: .episodeID).value
    let authorsField = container.tolerantValue(String.self, forKey: .authorsSummary)
    let typeField = container.tolerantValue(String.self, forKey: .type)
    let kindField = container.tolerantValue(String.self, forKey: .typeKind)
    let languageField = container.tolerantValue(String.self, forKey: .typeLang)
    let qualityField = container.tolerantValue(String.self, forKey: .qualityType)
    let isActiveField = container.tolerantValue(ProviderBoolean.self, forKey: .isActive)
    authorsSummary = authorsField.value
    type = typeField.value
    typeKind = kindField.value
    typeLang = languageField.value
    qualityType = qualityField.value
    isActive = isActiveField.value
    providedFields = Set([
      authorsField.isProvided ? .authors : nil,
      typeField.isProvided ? .type : nil,
      kindField.isProvided ? .kind : nil,
      languageField.isProvided ? .language : nil,
      qualityField.isProvided ? .quality : nil,
      isActiveField.isProvided ? .isActive : nil,
    ].compactMap(\.self))
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
      isActive: isActive?.value,
      providedFields: providedFields
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

private extension KeyedDecodingContainer {
  func tolerantValue<Value: Decodable>(
    _ type: Value.Type,
    forKey key: Key
  ) -> (value: Value?, isProvided: Bool) {
    guard contains(key) else { return (nil, false) }
    if (try? decodeNil(forKey: key)) == true { return (nil, true) }
    guard let value = try? decode(Value.self, forKey: key) else { return (nil, false) }
    return (value, true)
  }
}
