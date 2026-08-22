public struct Anime365Profile: Codable, Equatable, Sendable {
  public let id: Anime365ProfileID
  public let displayName: String?

  public init(id: Anime365ProfileID, displayName: String? = nil) {
    self.id = id
    self.displayName = displayName
  }
}
