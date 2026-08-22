import Foundation

private enum Anime365IdentifierValue {
  static func validate(_ rawValue: String) -> String? {
    rawValue.isEmpty ? nil : rawValue
  }

  static func decode(from decoder: any Decoder, name: String) throws -> String {
    let rawValue = try decoder.singleValueContainer().decode(String.self)
    guard let rawValue = validate(rawValue) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "\(name) is empty")
      )
    }
    return rawValue
  }

  static func encode(_ rawValue: String, to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public struct Anime365ProfileID: Codable, Hashable, Sendable {
  public let rawValue: String

  public init?(_ rawValue: String) {
    guard let rawValue = Anime365IdentifierValue.validate(rawValue) else { return nil }
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    rawValue = try Anime365IdentifierValue.decode(from: decoder, name: "Anime365 Profile ID")
  }

  public func encode(to encoder: any Encoder) throws {
    try Anime365IdentifierValue.encode(rawValue, to: encoder)
  }
}

public struct SeriesID: Codable, Hashable, Sendable {
  public let rawValue: String

  public init?(_ rawValue: String) {
    guard let rawValue = Anime365IdentifierValue.validate(rawValue) else { return nil }
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    rawValue = try Anime365IdentifierValue.decode(from: decoder, name: "Series ID")
  }

  public func encode(to encoder: any Encoder) throws {
    try Anime365IdentifierValue.encode(rawValue, to: encoder)
  }
}

public struct EpisodeID: Codable, Hashable, Sendable {
  public let rawValue: String

  public init?(_ rawValue: String) {
    guard let rawValue = Anime365IdentifierValue.validate(rawValue) else { return nil }
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    rawValue = try Anime365IdentifierValue.decode(from: decoder, name: "Episode ID")
  }

  public func encode(to encoder: any Encoder) throws {
    try Anime365IdentifierValue.encode(rawValue, to: encoder)
  }
}

public struct TranslationID: Codable, Hashable, Sendable {
  public let rawValue: String

  public init?(_ rawValue: String) {
    guard let rawValue = Anime365IdentifierValue.validate(rawValue) else { return nil }
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    rawValue = try Anime365IdentifierValue.decode(from: decoder, name: "Translation ID")
  }

  public func encode(to encoder: any Encoder) throws {
    try Anime365IdentifierValue.encode(rawValue, to: encoder)
  }
}
