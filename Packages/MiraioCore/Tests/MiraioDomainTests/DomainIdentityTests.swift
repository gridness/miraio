import Foundation
import Testing

@testable import MiraioDomain

@Suite("Opaque Anime365 identifiers")
struct DomainIdentityTests {
  @Test("identifiers reject empty provider values")
  func rejectsEmptyValues() {
    #expect(Anime365ProfileID("") == nil)
    #expect(SeriesID("") == nil)
    #expect(EpisodeID("") == nil)
    #expect(TranslationID("") == nil)
  }

  @Test("identifiers preserve their provider value through Codable")
  func codableRepresentation() throws {
    let profileID = try #require(Anime365ProfileID("profile-42"))

    let encoded = try JSONEncoder().encode(profileID)
    #expect(String(decoding: encoded, as: UTF8.self) == #""profile-42""#)
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
