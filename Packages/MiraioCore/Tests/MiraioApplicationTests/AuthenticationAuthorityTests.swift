import Foundation
import MiraioDomain
import Testing

@testable import MiraioApplication

@Suite("Anime365 Profile authentication", .serialized)
struct AuthenticationAuthorityTests {
  @Test("cold launch without an Access Token settles signed out")
  func restoresSignedOutStateWithoutCredential() async {
    let authority = AuthenticationAuthority(
      remote: AuthenticationRemoteStub(),
      credentials: CredentialVaultStub(record: nil),
      protectedSession: ProtectedSessionStub(),
      now: { Date(timeIntervalSince1970: 1_000) }
    )

    await authority.restore()

    #expect(await authority.currentState == .signedOut)
  }

  @Test("cold launch verifies a Profile-bound Access Token before enabling protected access")
  func restoresSubscriberAfterVerification() async throws {
    let token = try #require(AccessToken("secret"))
    let profileID = try #require(Anime365ProfileID(42))
    let profile = Anime365Profile(id: profileID, displayName: "Mira")
    let authority = AuthenticationAuthority(
      remote: AuthenticationRemoteStub(
        profileResult: .success(
          Anime365ProfileVerification(profile: profile, eligibility: .active)
        )
      ),
      credentials: CredentialVaultStub(record: .bound(token, profileID: profileID)),
      protectedSession: ProtectedSessionStub(),
      now: { Date(timeIntervalSince1970: 1_000) }
    )

    await authority.restore()

    #expect(await authority.currentState == .subscriber(profile))
  }

  @Test("accepted sign-in stores only a Profile-bound Access Token")
  func signsInAndBindsCredentialToVerifiedProfile() async throws {
    let token = try #require(AccessToken("issued-token"))
    let profileID = try #require(Anime365ProfileID(42))
    let profile = Anime365Profile(id: profileID, displayName: "Mira")
    let vault = CredentialVaultStub(record: nil)
    let authority = AuthenticationAuthority(
      remote: AuthenticationRemoteStub(
        signInResult: .success(token),
        profileResult: .success(
          Anime365ProfileVerification(profile: profile, eligibility: .active)
        )
      ),
      credentials: vault,
      protectedSession: ProtectedSessionStub(),
      now: { Date(timeIntervalSince1970: 1_000) }
    )

    let outcome = await authority.signIn(email: "mira@example.com", password: "transient")

    #expect(outcome == .authenticated)
    #expect(await authority.currentState == .subscriber(profile))
    #expect(await vault.storedRecord == .bound(token, profileID: profileID))
  }

  @Test("foreground revalidates only after the settled fifteen-minute interval")
  func revalidatesAtSettledForegroundTrigger() async throws {
    let token = try #require(AccessToken("secret"))
    let profileID = try #require(Anime365ProfileID(42))
    let profile = Anime365Profile(id: profileID)
    let clock = DateBox(Date(timeIntervalSince1970: 1_000))
    let remote = AuthenticationRemoteRecorder(
      profileResult: Anime365ProfileVerification(profile: profile, eligibility: .active)
    )
    let authority = AuthenticationAuthority(
      remote: remote,
      credentials: CredentialVaultStub(record: .bound(token, profileID: profileID)),
      protectedSession: ProtectedSessionStub(),
      now: { clock.value }
    )
    await authority.restore()

    clock.value = Date(timeIntervalSince1970: 1_899)
    await authority.foregrounded()
    #expect(await remote.profileRequestCount == 1)

    clock.value = Date(timeIntervalSince1970: 1_901)
    await authority.foregrounded()
    #expect(await remote.profileRequestCount == 2)
  }

  @Test("a due verification gates new protected playback using the settled eligibility")
  func gatesProtectedOperationAfterDueVerification() async throws {
    let token = try #require(AccessToken("secret"))
    let profileID = try #require(Anime365ProfileID(42))
    let profile = Anime365Profile(id: profileID)
    let clock = DateBox(Date(timeIntervalSince1970: 1_000))
    let remote = SequencedAuthenticationRemote(
      profileResults: [
        .success(Anime365ProfileVerification(profile: profile, eligibility: .active)),
        .success(Anime365ProfileVerification(profile: profile, eligibility: .inactive)),
      ]
    )
    let authority = AuthenticationAuthority(
      remote: remote,
      credentials: CredentialVaultStub(record: .bound(token, profileID: profileID)),
      protectedSession: ProtectedSessionStub(),
      now: { clock.value }
    )
    await authority.restore()
    clock.value = Date(timeIntervalSince1970: 1_901)

    let decision = await authority.beginProtectedOperation()

    #expect(decision == .blocked(.subscriptionRequired))
  }

  @Test(
    "one Profile check disambiguates a protected 403 without speculative token deletion",
    arguments: ProtectedFailureScenario.all
  )
  func resolvesAmbiguousProtectedFailure(_ scenario: ProtectedFailureScenario) async throws {
    let token = try #require(AccessToken("secret"))
    let profileID = try #require(Anime365ProfileID(42))
    let profile = Anime365Profile(id: profileID)
    let vault = CredentialVaultStub(record: .bound(token, profileID: profileID))
    let remote = SequencedAuthenticationRemote(
      profileResults: [
        .success(Anime365ProfileVerification(profile: profile, eligibility: .active)),
        scenario.verificationResult(profile: profile),
      ]
    )
    let authority = AuthenticationAuthority(
      remote: remote,
      credentials: vault,
      protectedSession: ProtectedSessionStub(),
      now: { Date(timeIntervalSince1970: 1_000) }
    )
    await authority.restore()

    let resolution = await authority.resolveProtectedFailure()

    #expect(resolution == scenario.expectedResolution)
    #expect((await vault.storedRecord != nil) == scenario.retainsCredential)
  }

  @Test("a late sign-in completion cannot restore protected state after sign-out")
  func rejectsSignInCompletionObsoletedBySignOut() async throws {
    let token = try #require(AccessToken("late-token"))
    let profileID = try #require(Anime365ProfileID(42))
    let gate = AuthenticationGate()
    let vault = CredentialVaultStub(record: nil)
    let protectedSession = ProtectedSessionRecorder()
    let authority = AuthenticationAuthority(
      remote: GatedSignInRemote(
        gate: gate,
        token: token,
        verification: Anime365ProfileVerification(
          profile: Anime365Profile(id: profileID),
          eligibility: .active
        )
      ),
      credentials: vault,
      protectedSession: protectedSession,
      now: { Date(timeIntervalSince1970: 1_000) }
    )

    let lateSignIn = Task {
      await authority.signIn(email: "mira@example.com", password: "transient")
    }
    await gate.waitUntilSuspended()
    let signOut = await authority.signOut()
    await gate.resume()
    _ = await lateSignIn.value

    #expect(signOut == .signedOut)
    #expect(await authority.currentState == .signedOut)
    #expect(await vault.storedRecord == nil)
    #expect(await protectedSession.clearCount == 1)
  }

  @Test("an obsolete credential write cannot land after sign-out deletion")
  func rejectsCredentialWriteObsoletedBySignOut() async throws {
    let token = try #require(AccessToken("late-token"))
    let gate = AuthenticationGate()
    let vault = GatedStoreCredentialVault(gate: gate)
    let authority = AuthenticationAuthority(
      remote: AuthenticationRemoteStub(signInResult: .success(token)),
      credentials: vault,
      protectedSession: ProtectedSessionStub()
    )

    let lateSignIn = Task {
      await authority.signIn(email: "mira@example.com", password: "transient")
    }
    await gate.waitUntilSuspended()
    #expect(await authority.signOut() == .signedOut)
    await gate.resume()
    _ = await lateSignIn.value

    #expect(await authority.currentState == .signedOut)
    #expect(await vault.storedRecord == nil)
  }

  @Test("sign-in stays blocked until sign-out credential deletion settles")
  func blocksSignInDuringSignOutCleanup() async throws {
    let token = try #require(AccessToken("new-token"))
    let gate = AuthenticationGate()
    let vault = GatedDeleteCredentialVault(gate: gate)
    let authority = AuthenticationAuthority(
      remote: AuthenticationRemoteStub(signInResult: .success(token)),
      credentials: vault,
      protectedSession: ProtectedSessionStub()
    )

    let signOut = Task { await authority.signOut() }
    await gate.waitUntilSuspended()
    #expect(await authority.currentState == .incompleteSignOut)
    let overlappingSignIn = await authority.signIn(
      email: "other@example.com",
      password: "transient"
    )
    await gate.resume()

    #expect(overlappingSignIn == .blocked)
    #expect(await signOut.value == .signedOut)
    #expect(await authority.currentState == .signedOut)
    #expect(await vault.storedRecord == nil)
  }

  @Test("cold-launch credential restoration blocks implicit Profile replacement")
  func blocksSignInDuringColdLaunchRestore() async throws {
    let existingToken = try #require(AccessToken("existing-token"))
    let replacementToken = try #require(AccessToken("replacement-token"))
    let existingProfileID = try #require(Anime365ProfileID(42))
    let replacementProfileID = try #require(Anime365ProfileID(84))
    let existingProfile = Anime365Profile(id: existingProfileID)
    let replacementProfile = Anime365Profile(id: replacementProfileID)
    let gate = AuthenticationGate()
    let vault = GatedLoadCredentialVault(
      gate: gate,
      record: .bound(existingToken, profileID: existingProfileID)
    )
    let authority = AuthenticationAuthority(
      remote: ProfileMappedAuthenticationRemote(
        signInToken: replacementToken,
        existingToken: existingToken,
        existingVerification: Anime365ProfileVerification(
          profile: existingProfile,
          eligibility: .active
        ),
        replacementVerification: Anime365ProfileVerification(
          profile: replacementProfile,
          eligibility: .active
        )
      ),
      credentials: vault,
      protectedSession: ProtectedSessionStub()
    )

    let restore = Task { await authority.restore() }
    await gate.waitUntilSuspended()
    let overlappingSignIn = await authority.signIn(
      email: "other@example.com",
      password: "transient"
    )
    await gate.resume()
    await restore.value

    #expect(overlappingSignIn == .blocked)
    #expect(await authority.currentState == .subscriber(existingProfile))
    #expect(await vault.storedRecord == .bound(existingToken, profileID: existingProfileID))
  }

  @Test("failed credential deletion persists a retryable incomplete sign-out")
  func persistsAndRetriesIncompleteSignOut() async throws {
    let token = try #require(AccessToken("secret"))
    let profileID = try #require(Anime365ProfileID(42))
    let profile = Anime365Profile(id: profileID)
    let vault = RecoveringCredentialVault(
      record: .bound(token, profileID: profileID),
      deletionFails: true
    )
    let authority = AuthenticationAuthority(
      remote: AuthenticationRemoteStub(
        profileResult: .success(
          Anime365ProfileVerification(profile: profile, eligibility: .active)
        )
      ),
      credentials: vault,
      protectedSession: ProtectedSessionStub(),
      now: { Date(timeIntervalSince1970: 1_000) }
    )
    await authority.restore()

    #expect(await authority.signOut() == .incomplete)
    #expect(await authority.currentState == .incompleteSignOut)
    #expect(await authority.beginProtectedOperation() == .blocked(.incompleteSignOut))

    let relaunched = AuthenticationAuthority(
      remote: AuthenticationRemoteStub(),
      credentials: vault,
      protectedSession: ProtectedSessionStub(),
      now: { Date(timeIntervalSince1970: 2_000) }
    )
    await relaunched.restore()
    #expect(await relaunched.currentState == .incompleteSignOut)

    await vault.setDeletionFails(false)
    #expect(await relaunched.retryIncompleteSignOut() == .signedOut)
    #expect(await relaunched.currentState == .signedOut)
    #expect(await vault.storedRecord == nil)
  }

  @Test("observers receive immutable authentication transitions")
  func broadcastsAuthenticationStates() async throws {
    let token = try #require(AccessToken("secret"))
    let profileID = try #require(Anime365ProfileID(42))
    let profile = Anime365Profile(id: profileID)
    let gate = AuthenticationGate()
    let authority = AuthenticationAuthority(
      remote: GatedProfileRemote(
        gate: gate,
        verification: Anime365ProfileVerification(profile: profile, eligibility: .active)
      ),
      credentials: CredentialVaultStub(record: .bound(token, profileID: profileID)),
      protectedSession: ProtectedSessionStub(),
      now: { Date(timeIntervalSince1970: 1_000) }
    )
    let stream = await authority.states()
    var iterator = stream.makeAsyncIterator()

    let restore = Task { await authority.restore() }
    #expect(await iterator.next() == .verifying)
    await gate.resume()
    await restore.value
    #expect(await iterator.next() == .subscriber(profile))
  }

  @Test("explicit Refresh revalidates Subscription Eligibility immediately")
  func refreshesEligibilityExplicitly() async throws {
    let token = try #require(AccessToken("secret"))
    let profileID = try #require(Anime365ProfileID(42))
    let profile = Anime365Profile(id: profileID)
    let remote = AuthenticationRemoteRecorder(
      profileResult: Anime365ProfileVerification(profile: profile, eligibility: .active)
    )
    let authority = AuthenticationAuthority(
      remote: remote,
      credentials: CredentialVaultStub(record: .bound(token, profileID: profileID)),
      protectedSession: ProtectedSessionStub(),
      now: { Date(timeIntervalSince1970: 1_000) }
    )
    await authority.restore()

    await authority.refreshEligibility()

    #expect(await remote.profileRequestCount == 2)
  }

  @Test("sign-out cancels authenticated requests before they can complete")
  func cancelsAuthenticatedRequestsOnSignOut() async {
    let remote = CancellableAuthenticationRemote()
    let authority = AuthenticationAuthority(
      remote: remote,
      credentials: CredentialVaultStub(record: nil),
      protectedSession: ProtectedSessionStub(),
      now: { Date(timeIntervalSince1970: 1_000) }
    )
    let signIn = Task {
      await authority.signIn(email: "mira@example.com", password: "transient")
    }
    await remote.waitUntilRequested()

    _ = await authority.signOut()
    await remote.finishCancellation()
    _ = await signIn.value

    #expect(await remote.cancellationCount == 1)
  }

  @Test("a failed Profile binding exposes credential unavailability")
  func reportsCredentialBindingFailure() async throws {
    let token = try #require(AccessToken("issued-token"))
    let profileID = try #require(Anime365ProfileID(42))
    let profile = Anime365Profile(id: profileID)
    let authority = AuthenticationAuthority(
      remote: AuthenticationRemoteStub(
        signInResult: .success(token),
        profileResult: .success(
          Anime365ProfileVerification(profile: profile, eligibility: .active)
        )
      ),
      credentials: FailingBindCredentialVault(),
      protectedSession: ProtectedSessionStub(),
      now: { Date(timeIntervalSince1970: 1_000) }
    )

    let outcome = await authority.signIn(email: "mira@example.com", password: "transient")

    #expect(outcome == .credentialUnavailable)
    #expect(await authority.currentState == .credentialUnavailable)
  }

  @Test("temporary verification failure preserves the verified Anime365 Profile")
  func preservesProfileWhenEligibilityBecomesUnknown() async throws {
    let token = try #require(AccessToken("secret"))
    let profileID = try #require(Anime365ProfileID(42))
    let profile = Anime365Profile(id: profileID, displayName: "Mira")
    let authority = AuthenticationAuthority(
      remote: SequencedAuthenticationRemote(
        profileResults: [
          .success(Anime365ProfileVerification(profile: profile, eligibility: .active)),
          .failure(.unavailable),
        ]
      ),
      credentials: CredentialVaultStub(record: .bound(token, profileID: profileID)),
      protectedSession: ProtectedSessionStub(),
      now: { Date(timeIntervalSince1970: 1_000) }
    )
    await authority.restore()

    await authority.refreshEligibility()

    #expect(await authority.currentState == .authenticatedProfile(profile, eligibility: .unknown))
  }

  @Test("an unreadable Keychain is credential unavailable, not signed out")
  func distinguishesCredentialUnavailableState() async {
    let authority = AuthenticationAuthority(
      remote: AuthenticationRemoteStub(),
      credentials: UnavailableCredentialVault(),
      protectedSession: ProtectedSessionStub()
    )

    await authority.restore()

    #expect(await authority.currentState == .credentialUnavailable)
  }

  @Test("an unverified pending Access Token remains verifying after temporary failure")
  func preservesVerifyingStateForPendingCredential() async throws {
    let token = try #require(AccessToken("pending-token"))
    let authority = AuthenticationAuthority(
      remote: AuthenticationRemoteStub(profileResult: .failure(.unavailable)),
      credentials: CredentialVaultStub(record: .pending(token)),
      protectedSession: ProtectedSessionStub()
    )

    await authority.restore()

    #expect(await authority.currentState == .verifying)
  }

  @Test("another Profile cannot sign in until explicit local sign-out")
  func blocksProfileReplacementWithoutSignOut() async throws {
    let token = try #require(AccessToken("secret"))
    let profileID = try #require(Anime365ProfileID(42))
    let profile = Anime365Profile(id: profileID)
    let authority = AuthenticationAuthority(
      remote: AuthenticationRemoteStub(
        profileResult: .success(
          Anime365ProfileVerification(profile: profile, eligibility: .active)
        )
      ),
      credentials: CredentialVaultStub(record: .bound(token, profileID: profileID)),
      protectedSession: ProtectedSessionStub()
    )
    await authority.restore()

    let outcome = await authority.signIn(email: "other@example.com", password: "transient")

    #expect(outcome == .blocked)
    #expect(await authority.currentState == .subscriber(profile))
  }
}

struct ProtectedFailureScenario: Sendable, CustomTestStringConvertible {
  enum VerificationResult: Sendable {
    case invalidAuthentication
    case inactive
    case active
    case unavailable
  }

  let name: String
  let result: VerificationResult
  let expectedResolution: ProtectedFailureResolution
  let retainsCredential: Bool

  var testDescription: String { name }

  func verificationResult(
    profile: Anime365Profile
  ) -> Result<Anime365ProfileVerification, AuthenticationRemoteFailure> {
    switch result {
    case .invalidAuthentication:
      .failure(.invalidAccessToken)
    case .inactive:
      .success(Anime365ProfileVerification(profile: profile, eligibility: .inactive))
    case .active:
      .success(Anime365ProfileVerification(profile: profile, eligibility: .active))
    case .unavailable:
      .failure(.unavailable)
    }
  }

  static let all: [Self] = [
    Self(
      name: "invalid authentication",
      result: .invalidAuthentication,
      expectedResolution: .authenticationRequired,
      retainsCredential: false
    ),
    Self(
      name: "inactive Subscription",
      result: .inactive,
      expectedResolution: .subscriptionRequired,
      retainsCredential: true
    ),
    Self(
      name: "active Subscription",
      result: .active,
      expectedResolution: .protectedResourceFailure,
      retainsCredential: true
    ),
    Self(
      name: "unavailable verification",
      result: .unavailable,
      expectedResolution: .verificationUnavailable,
      retainsCredential: true
    ),
  ]
}

private struct AuthenticationRemoteStub: Anime365AuthenticationRemote {
  let signInResult: Result<AccessToken, AuthenticationRemoteFailure>
  let profileResult: Result<Anime365ProfileVerification, AuthenticationRemoteFailure>

  init(
    signInResult: Result<AccessToken, AuthenticationRemoteFailure> = .failure(.unavailable),
    profileResult: Result<Anime365ProfileVerification, AuthenticationRemoteFailure> =
      .failure(.unavailable)
  ) {
    self.signInResult = signInResult
    self.profileResult = profileResult
  }

  func signIn(email: String, password: String) async throws -> AccessToken {
    try signInResult.get()
  }

  func profile(using token: AccessToken) async throws -> Anime365ProfileVerification {
    try profileResult.get()
  }
}

private actor CredentialVaultStub: AccessTokenVault {
  private var record: StoredAccessToken?

  init(record: StoredAccessToken?) {
    self.record = record
  }

  func load() throws -> StoredAccessToken? { record }
  func storePending(_ token: AccessToken, generation: UInt64) throws {
    record = .pending(token)
  }
  func bind(_ token: AccessToken, to profileID: Anime365ProfileID, generation: UInt64) throws {
    record = .bound(token, profileID: profileID)
  }
  func delete(generation: UInt64) throws { record = nil }
  func hasIncompleteSignOut() -> Bool { false }
  func markIncompleteSignOut() {}
  func clearIncompleteSignOut() {}

  var storedRecord: StoredAccessToken? { record }
}

private actor RecoveringCredentialVault: AccessTokenVault {
  private var record: StoredAccessToken?
  private var deletionFails: Bool
  private var incompleteSignOut = false

  init(record: StoredAccessToken?, deletionFails: Bool) {
    self.record = record
    self.deletionFails = deletionFails
  }

  func load() throws -> StoredAccessToken? { record }
  func storePending(_ token: AccessToken, generation: UInt64) throws {
    record = .pending(token)
  }
  func bind(_ token: AccessToken, to profileID: Anime365ProfileID, generation: UInt64) throws {
    record = .bound(token, profileID: profileID)
  }
  func delete(generation: UInt64) throws {
    if deletionFails { throw CredentialVaultTestFailure.deletionFailed }
    record = nil
  }
  func hasIncompleteSignOut() -> Bool { incompleteSignOut }
  func markIncompleteSignOut() { incompleteSignOut = true }
  func clearIncompleteSignOut() { incompleteSignOut = false }
  func setDeletionFails(_ value: Bool) { deletionFails = value }

  var storedRecord: StoredAccessToken? { record }
}

private actor GatedStoreCredentialVault: AccessTokenVault {
  private let gate: AuthenticationGate
  private var record: StoredAccessToken?
  private var latestGeneration: UInt64 = 0

  init(gate: AuthenticationGate) {
    self.gate = gate
  }

  func load() -> StoredAccessToken? { record }
  func storePending(_ token: AccessToken, generation: UInt64) async throws {
    await gate.suspend()
    guard generation >= latestGeneration else {
      throw CredentialVaultTestFailure.obsoleteMutation
    }
    latestGeneration = generation
    record = .pending(token)
  }
  func bind(_ token: AccessToken, to profileID: Anime365ProfileID, generation: UInt64) {
    latestGeneration = max(latestGeneration, generation)
    record = .bound(token, profileID: profileID)
  }
  func delete(generation: UInt64) {
    latestGeneration = max(latestGeneration, generation)
    record = nil
  }
  func hasIncompleteSignOut() -> Bool { false }
  func markIncompleteSignOut() {}
  func clearIncompleteSignOut() {}

  var storedRecord: StoredAccessToken? { record }
}

private actor GatedDeleteCredentialVault: AccessTokenVault {
  private let gate: AuthenticationGate
  private var record: StoredAccessToken?
  private var latestGeneration: UInt64 = 0

  init(gate: AuthenticationGate) {
    self.gate = gate
  }

  func load() -> StoredAccessToken? { record }
  func storePending(_ token: AccessToken, generation: UInt64) throws {
    try accept(generation)
    record = .pending(token)
  }
  func bind(_ token: AccessToken, to profileID: Anime365ProfileID, generation: UInt64) throws {
    try accept(generation)
    record = .bound(token, profileID: profileID)
  }
  func delete(generation: UInt64) async throws {
    await gate.suspend()
    try accept(generation)
    record = nil
  }
  func hasIncompleteSignOut() -> Bool { false }
  func markIncompleteSignOut() {}
  func clearIncompleteSignOut() {}

  var storedRecord: StoredAccessToken? { record }

  private func accept(_ generation: UInt64) throws {
    guard generation >= latestGeneration else {
      throw CredentialVaultTestFailure.obsoleteMutation
    }
    latestGeneration = generation
  }
}

private actor GatedLoadCredentialVault: AccessTokenVault {
  private let gate: AuthenticationGate
  private var record: StoredAccessToken?
  private var latestGeneration: UInt64 = 0

  init(gate: AuthenticationGate, record: StoredAccessToken?) {
    self.gate = gate
    self.record = record
  }

  func load() async -> StoredAccessToken? {
    let capturedRecord = record
    await gate.suspend()
    return capturedRecord
  }
  func storePending(_ token: AccessToken, generation: UInt64) throws {
    try accept(generation)
    record = .pending(token)
  }
  func bind(_ token: AccessToken, to profileID: Anime365ProfileID, generation: UInt64) throws {
    try accept(generation)
    record = .bound(token, profileID: profileID)
  }
  func delete(generation: UInt64) throws {
    try accept(generation)
    record = nil
  }
  func hasIncompleteSignOut() -> Bool { false }
  func markIncompleteSignOut() {}
  func clearIncompleteSignOut() {}

  var storedRecord: StoredAccessToken? { record }

  private func accept(_ generation: UInt64) throws {
    guard generation >= latestGeneration else {
      throw CredentialVaultTestFailure.obsoleteMutation
    }
    latestGeneration = generation
  }
}

private actor FailingBindCredentialVault: AccessTokenVault {
  private var record: StoredAccessToken?

  func load() -> StoredAccessToken? { record }
  func storePending(_ token: AccessToken, generation: UInt64) { record = .pending(token) }
  func bind(_ token: AccessToken, to profileID: Anime365ProfileID, generation: UInt64) throws {
    throw CredentialVaultTestFailure.bindingFailed
  }
  func delete(generation: UInt64) { record = nil }
  func hasIncompleteSignOut() -> Bool { false }
  func markIncompleteSignOut() {}
  func clearIncompleteSignOut() {}
}

private actor UnavailableCredentialVault: AccessTokenVault {
  func load() throws -> StoredAccessToken? { throw CredentialVaultTestFailure.unavailable }
  func storePending(_ token: AccessToken, generation: UInt64) throws {
    throw CredentialVaultTestFailure.unavailable
  }
  func bind(_ token: AccessToken, to profileID: Anime365ProfileID, generation: UInt64) throws {
    throw CredentialVaultTestFailure.unavailable
  }
  func delete(generation: UInt64) throws { throw CredentialVaultTestFailure.unavailable }
  func hasIncompleteSignOut() -> Bool { false }
  func markIncompleteSignOut() {}
  func clearIncompleteSignOut() {}
}

private enum CredentialVaultTestFailure: Error {
  case deletionFailed
  case bindingFailed
  case unavailable
  case obsoleteMutation
}

private actor ProtectedSessionStub: ProtectedSessionClearing {
  func clearProtectedSession() async {}
}

private actor ProtectedSessionRecorder: ProtectedSessionClearing {
  private(set) var clearCount = 0

  func clearProtectedSession() async {
    clearCount += 1
  }
}

private actor AuthenticationRemoteRecorder: Anime365AuthenticationRemote {
  private let profileResult: Anime365ProfileVerification
  private(set) var profileRequestCount = 0

  init(profileResult: Anime365ProfileVerification) {
    self.profileResult = profileResult
  }

  func signIn(email: String, password: String) async throws -> AccessToken {
    throw AuthenticationRemoteFailure.unavailable
  }

  func profile(using token: AccessToken) async throws -> Anime365ProfileVerification {
    profileRequestCount += 1
    return profileResult
  }
}

private struct ProfileMappedAuthenticationRemote: Anime365AuthenticationRemote {
  let signInToken: AccessToken
  let existingToken: AccessToken
  let existingVerification: Anime365ProfileVerification
  let replacementVerification: Anime365ProfileVerification

  func signIn(email: String, password: String) -> AccessToken { signInToken }

  func profile(using token: AccessToken) throws -> Anime365ProfileVerification {
    token == existingToken ? existingVerification : replacementVerification
  }
}

private actor CancellableAuthenticationRemote: Anime365AuthenticationRemote {
  private var request: CheckedContinuation<AccessToken, any Error>?
  private var requestWaiters: [CheckedContinuation<Void, Never>] = []
  private(set) var cancellationCount = 0

  func signIn(email: String, password: String) async throws -> AccessToken {
    let waiters = requestWaiters
    requestWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
    return try await withCheckedThrowingContinuation { continuation in
      request = continuation
    }
  }

  func profile(using token: AccessToken) async throws -> Anime365ProfileVerification {
    throw AuthenticationRemoteFailure.unavailable
  }

  func cancelAllRequests() {
    cancellationCount += 1
    request?.resume(throwing: CancellationError())
    request = nil
  }

  func waitUntilRequested() async {
    guard request == nil else { return }
    await withCheckedContinuation { continuation in
      requestWaiters.append(continuation)
    }
  }

  func finishCancellation() {
    request?.resume(throwing: CancellationError())
    request = nil
  }
}

private actor SequencedAuthenticationRemote: Anime365AuthenticationRemote {
  private var profileResults: [Result<Anime365ProfileVerification, AuthenticationRemoteFailure>]

  init(
    profileResults: [Result<Anime365ProfileVerification, AuthenticationRemoteFailure>]
  ) {
    self.profileResults = profileResults
  }

  func signIn(email: String, password: String) async throws -> AccessToken {
    throw AuthenticationRemoteFailure.unavailable
  }

  func profile(using token: AccessToken) async throws -> Anime365ProfileVerification {
    guard !profileResults.isEmpty else { throw AuthenticationRemoteFailure.unavailable }
    return try profileResults.removeFirst().get()
  }
}

private final class DateBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: Date

  init(_ value: Date) {
    storage = value
  }

  var value: Date {
    get { lock.withLock { storage } }
    set { lock.withLock { storage = newValue } }
  }
}

private struct GatedSignInRemote: Anime365AuthenticationRemote {
  let gate: AuthenticationGate
  let token: AccessToken
  let verification: Anime365ProfileVerification

  func signIn(email: String, password: String) async throws -> AccessToken {
    await gate.suspend()
    return token
  }

  func profile(using token: AccessToken) async throws -> Anime365ProfileVerification {
    verification
  }
}

private struct GatedProfileRemote: Anime365AuthenticationRemote {
  let gate: AuthenticationGate
  let verification: Anime365ProfileVerification

  func signIn(email: String, password: String) async throws -> AccessToken {
    throw AuthenticationRemoteFailure.unavailable
  }

  func profile(using token: AccessToken) async throws -> Anime365ProfileVerification {
    await gate.suspend()
    return verification
  }
}

private actor AuthenticationGate {
  private var isSuspended = false
  private var suspension: CheckedContinuation<Void, Never>?
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func suspend() async {
    isSuspended = true
    let pendingWaiters = waiters
    waiters.removeAll()
    for waiter in pendingWaiters { waiter.resume() }
    await withCheckedContinuation { continuation in
      suspension = continuation
    }
  }

  func waitUntilSuspended() async {
    guard !isSuspended else { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func resume() {
    suspension?.resume()
    suspension = nil
  }
}
