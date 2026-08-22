import Foundation
import MiraioDomain

public protocol CatalogueRemote: Sendable {
  func loadSeries(query: SeriesQuery, cursor: SeriesCursor?) async throws -> CataloguePage
  func loadSeriesDetails(id: SeriesID) async throws -> SeriesDetails
}

public enum CatalogueFailure: Error, Equatable, Sendable {
  case cancelled
  case transportUnavailable
  case serviceRejected(code: Int)
  case notFound
  case invalidQuery
  case unusableResponse
  case retryAfter(seconds: TimeInterval)
}
