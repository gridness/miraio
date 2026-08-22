import Foundation

public protocol RedactedDiagnostics: Sendable {
  func record(_ event: RedactedDiagnosticEvent) async
}

public struct RedactedDiagnosticEvent: Codable, Equatable, Sendable {
  public enum Category: String, Codable, Sendable {
    case lifecycle
  }

  public enum Outcome: String, Codable, Sendable {
    case obsoleteCompletion = "obsolete_completion"
  }

  public let attemptID: UUID
  public let category: Category
  public let outcome: Outcome

  public init(attemptID: UUID, category: Category, outcome: Outcome) {
    self.attemptID = attemptID
    self.category = category
    self.outcome = outcome
  }

  public func exportLine() throws -> String {
    let record = ExportRecord(
      attemptID: attemptID.uuidString.replacingOccurrences(of: "-", with: ""),
      category: category,
      outcome: outcome
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(record), as: UTF8.self)
  }
}

private struct ExportRecord: Encodable {
  let attemptID: String
  let category: RedactedDiagnosticEvent.Category
  let outcome: RedactedDiagnosticEvent.Outcome

  enum CodingKeys: String, CodingKey {
    case attemptID = "attempt_id"
    case category
    case outcome
  }
}
