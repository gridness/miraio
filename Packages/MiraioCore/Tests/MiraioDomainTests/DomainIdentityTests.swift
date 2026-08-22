import Foundation
import Testing

@testable import MiraioDomain

@Suite("Opaque Anime365 identifiers")
struct DomainIdentityTests {
  @Test("identifiers reject non-positive provider values")
  func rejectsNonPositiveValues() {
    #expect(Anime365ProfileID(0) == nil)
    #expect(SeriesID(-1) == nil)
    #expect(EpisodeID(0) == nil)
    #expect(TranslationID(-1) == nil)
  }

  @Test("identifiers preserve their provider value through Codable")
  func codableRepresentation() throws {
    let profileID = try #require(Anime365ProfileID(42))

    let encoded = try JSONEncoder().encode(profileID)
    #expect(String(decoding: encoded, as: UTF8.self) == "42")
    #expect(try JSONDecoder().decode(Anime365ProfileID.self, from: encoded) == profileID)
  }
}

@Suite("Subscription Eligibility")
struct SubscriptionEligibilityTests {
  @Test(arguments: [
    SubscriptionEligibility.unknown,
    .inactive,
    .active,
  ])
  func hasThreeStableStates(_ eligibility: SubscriptionEligibility) throws {
    let encoded = try JSONEncoder().encode(eligibility)
    let decoded = try JSONDecoder().decode(SubscriptionEligibility.self, from: encoded)

    #expect(decoded == eligibility)
  }
}
