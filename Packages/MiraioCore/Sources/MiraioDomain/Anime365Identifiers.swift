import Foundation

private enum Anime365IdentifierValue {
  static func validate(_ rawValue: Int) -> Int? {
    rawValue > 0 ? rawValue : nil
  }

  static func decode(from decoder: any Decoder, name: String) throws -> Int {
    let rawValue = try decoder.singleValueContainer().decode(Int.self)
    guard let rawValue = validate(rawValue) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "\(name) is empty")
      )
    }
    return rawValue
  }

  static func encode(_ rawValue: Int, to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public struct Anime365ProfileID: Codable, Hashable, Sendable {
  public let rawValue: Int

  public init?(_ rawValue: Int) {
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
  public let rawValue: Int

  public init?(_ rawValue: Int) {
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
  public let rawValue: Int

  public init?(_ rawValue: Int) {
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
  public let rawValue: Int

  public init?(_ rawValue: Int) {
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
