import Foundation

public struct Anime365ProfileID: Codable, Hashable, Sendable {
  public let rawValue: String

  public init?(_ rawValue: String) {
    guard !rawValue.isEmpty else { return nil }
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    let rawValue = try decoder.singleValueContainer().decode(String.self)
    guard let value = Self(rawValue) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Anime365 Profile ID is empty")
      )
    }
    self = value
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public struct SeriesID: Codable, Hashable, Sendable {
  public let rawValue: String

  public init?(_ rawValue: String) {
    guard !rawValue.isEmpty else { return nil }
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    let rawValue = try decoder.singleValueContainer().decode(String.self)
    guard let value = Self(rawValue) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Series ID is empty")
      )
    }
    self = value
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public struct EpisodeID: Codable, Hashable, Sendable {
  public let rawValue: String

  public init?(_ rawValue: String) {
    guard !rawValue.isEmpty else { return nil }
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    let rawValue = try decoder.singleValueContainer().decode(String.self)
    guard let value = Self(rawValue) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Episode ID is empty")
      )
    }
    self = value
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public struct TranslationID: Codable, Hashable, Sendable {
  public let rawValue: String

  public init?(_ rawValue: String) {
    guard !rawValue.isEmpty else { return nil }
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    let rawValue = try decoder.singleValueContainer().decode(String.self)
    guard let value = Self(rawValue) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Translation ID is empty")
      )
    }
    self = value
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
