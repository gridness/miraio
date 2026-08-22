import Foundation
import Testing

@testable import MiraioApplication

@Suite("Redacted diagnostics")
struct RedactedDiagnosticsTests {
  @Test("exported evidence contains only a random attempt identifier and categories")
  func exportsOnlyAllowedFields() throws {
    let event = RedactedDiagnosticEvent(
      attemptID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
      category: .lifecycle,
      outcome: .obsoleteCompletion
    )

    #expect(
      try event.exportLine()
        == #"{"attempt_id":"AAAAAAAABBBBCCCCDDDDEEEEEEEEEEEE","category":"lifecycle","outcome":"obsolete_completion"}"#
    )
  }

  @Test("Access Tokens redact their printable and debug representations")
  func redactsAccessTokenRepresentations() throws {
    let token = try #require(AccessToken("must-not-appear"))

    #expect(String(describing: token) == "<redacted Access Token>")
    #expect(String(reflecting: token) == "<redacted Access Token>")
  }
}
