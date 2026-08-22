import Foundation
import MiraioDomain

public struct AccessToken: CustomDebugStringConvertible, CustomStringConvertible, Equatable, Sendable {
  package let rawValue: String

  package init?(_ rawValue: String) {
    guard !rawValue.isEmpty else { return nil }
    self.rawValue = rawValue
  }

  public var description: String { "<redacted Access Token>" }
  public var debugDescription: String { description }
}

public enum StoredAccessToken: Equatable, Sendable {
  case pending(AccessToken)
  case bound(AccessToken, profileID: Anime365ProfileID)
}

public struct Anime365ProfileVerification: Equatable, Sendable {
  public let profile: Anime365Profile
  public let eligibility: SubscriptionEligibility

  public init(profile: Anime365Profile, eligibility: SubscriptionEligibility) {
    self.profile = profile
    self.eligibility = eligibility
  }
}

public enum AuthenticationRemoteFailure: Error, Equatable, Sendable {
  case rejectedSignIn
  case invalidAccessToken
  case unavailable
  case unusableResponse
  case serviceRejected
}

public protocol Anime365AuthenticationRemote: Sendable {
  func signIn(email: String, password: String) async throws -> AccessToken
  func profile(using token: AccessToken) async throws -> Anime365ProfileVerification
  func cancelAllRequests() async
}

extension Anime365AuthenticationRemote {
  public func cancelAllRequests() async {}
}

public protocol AccessTokenVault: Sendable {
  func load() async throws -> StoredAccessToken?
  /// Implementations reject a mutation older than any generation already observed.
  func storePending(_ token: AccessToken, generation: UInt64) async throws
  func bind(
    _ token: AccessToken,
    to profileID: Anime365ProfileID,
    generation: UInt64
  ) async throws
  func delete(generation: UInt64) async throws
  func hasIncompleteSignOut() async -> Bool
  func markIncompleteSignOut() async
  func clearIncompleteSignOut() async
}

public protocol ProtectedSessionClearing: Sendable {
  func clearProtectedSession() async
}

public enum AuthenticationState: Equatable, Sendable {
  case signedOut
  case credentialUnavailable
  case verifying
  case authenticatedProfile(Anime365Profile, eligibility: SubscriptionEligibility)
  case subscriber(Anime365Profile)
  case incompleteSignOut
}

public enum AuthenticationActionOutcome: Equatable, Sendable {
  case authenticated
  case rejected
  case verificationUnavailable
  case credentialUnavailable
  case unavailable
  case blocked
}

public enum ProtectedAccessBlock: Equatable, Sendable {
  case signInRequired
  case credentialUnavailable
  case verificationRequired
  case subscriptionRequired
  case incompleteSignOut
}

public enum ProtectedAccessDecision: Equatable, Sendable {
  case allowed(AccessToken)
  case blocked(ProtectedAccessBlock)
}

public enum ProtectedFailureResolution: Equatable, Sendable {
  case authenticationRequired
  case subscriptionRequired
  case protectedResourceFailure
  case verificationUnavailable
}

public enum SignOutOutcome: Equatable, Sendable {
  case signedOut
  case incomplete
}

public actor AuthenticationAuthority {
  public private(set) var currentState: AuthenticationState = .signedOut

  private let remote: any Anime365AuthenticationRemote
  private let credentials: any AccessTokenVault
  private let protectedSession: any ProtectedSessionClearing
  private let now: @Sendable () -> Date
  private var lastSuccessfulVerification: Date?
  private var activeCredential: StoredAccessToken?
  private var verifiedProfile: Anime365Profile?
  private var generation: UInt64 = 0
  private var nextObserverID: UInt64 = 0
  private var observers: [UInt64: AsyncStream<AuthenticationState>.Continuation] = [:]

  public init(
    remote: any Anime365AuthenticationRemote,
    credentials: any AccessTokenVault,
    protectedSession: any ProtectedSessionClearing,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.remote = remote
    self.credentials = credentials
    self.protectedSession = protectedSession
    self.now = now
  }

  public func states() -> AsyncStream<AuthenticationState> {
    nextObserverID &+= 1
    let observerID = nextObserverID
    let (stream, continuation) = AsyncStream.makeStream(of: AuthenticationState.self)
    observers[observerID] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeObserver(observerID) }
    }
    return stream
  }

  public func restore() async {
    generation &+= 1
    let submittedGeneration = generation
    if await credentials.hasIncompleteSignOut() {
      guard generation == submittedGeneration else { return }
      transition(to: .incompleteSignOut)
      return
    }

    do {
      guard let storedToken = try await credentials.load() else {
        guard generation == submittedGeneration else { return }
        transition(to: .signedOut)
        return
      }
      guard generation == submittedGeneration else { return }
      activeCredential = storedToken
      transition(to: .verifying)
      await verify(storedToken, generation: submittedGeneration)
    } catch {
      guard generation == submittedGeneration else { return }
      transition(to: .credentialUnavailable)
    }
  }

  public func signIn(email: String, password: String) async -> AuthenticationActionOutcome {
    guard currentState == .signedOut else { return .blocked }
    generation &+= 1
    let submittedGeneration = generation
    transition(to: .verifying)

    let token: AccessToken
    do {
      token = try await remote.signIn(email: email, password: password)
      guard generation == submittedGeneration else { return .blocked }
    } catch AuthenticationRemoteFailure.rejectedSignIn {
      guard generation == submittedGeneration else { return .blocked }
      transition(to: .signedOut)
      return .rejected
    } catch {
      guard generation == submittedGeneration else { return .blocked }
      transition(to: .signedOut)
      return .unavailable
    }

    do {
      try await credentials.storePending(token, generation: submittedGeneration)
      guard generation == submittedGeneration else { return .blocked }
      activeCredential = .pending(token)
    } catch {
      guard generation == submittedGeneration else { return .blocked }
      transition(to: .credentialUnavailable)
      return .credentialUnavailable
    }

    await verify(.pending(token), generation: submittedGeneration)
    guard generation == submittedGeneration else { return .blocked }
    switch currentState {
    case .subscriber, .authenticatedProfile:
      return .authenticated
    case .credentialUnavailable:
      return .credentialUnavailable
    case .verifying:
      return .verificationUnavailable
    case .signedOut, .incompleteSignOut:
      return .unavailable
    }
  }

  public func foregrounded() async {
    guard isVerificationDue, let activeCredential else { return }
    generation &+= 1
    let submittedGeneration = generation

    transition(to: .verifying)
    await verify(activeCredential, generation: submittedGeneration)
  }

  public func refreshEligibility() async {
    guard let activeCredential else { return }
    generation &+= 1
    let submittedGeneration = generation
    transition(to: .verifying)
    await verify(activeCredential, generation: submittedGeneration)
  }

  public func beginProtectedOperation() async -> ProtectedAccessDecision {
    if isVerificationDue, let activeCredential {
      generation &+= 1
      let submittedGeneration = generation
      transition(to: .verifying)
      await verify(activeCredential, generation: submittedGeneration)
    }

    switch currentState {
    case .subscriber:
      guard let token = activeCredential?.token else {
        return .blocked(.credentialUnavailable)
      }
      return .allowed(token)
    case .signedOut:
      return .blocked(.signInRequired)
    case .credentialUnavailable:
      return .blocked(.credentialUnavailable)
    case .verifying:
      return .blocked(.verificationRequired)
    case .authenticatedProfile(_, let eligibility):
      return eligibility == .inactive
        ? .blocked(.subscriptionRequired)
        : .blocked(.verificationRequired)
    case .incompleteSignOut:
      return .blocked(.incompleteSignOut)
    }
  }

  public func resolveProtectedFailure() async -> ProtectedFailureResolution {
    guard let activeCredential else { return .authenticationRequired }
    generation &+= 1
    let submittedGeneration = generation
    transition(to: .verifying)
    await verify(activeCredential, generation: submittedGeneration)

    switch currentState {
    case .signedOut:
      return .authenticationRequired
    case .subscriber:
      return .protectedResourceFailure
    case .authenticatedProfile(_, let eligibility):
      return eligibility == .inactive ? .subscriptionRequired : .verificationUnavailable
    case .credentialUnavailable, .verifying, .incompleteSignOut:
      return .verificationUnavailable
    }
  }

  private var isVerificationDue: Bool {
    guard let lastSuccessfulVerification else { return activeCredential != nil }
    return now().timeIntervalSince(lastSuccessfulVerification) > 15 * 60
  }

  public func signOut() async -> SignOutOutcome {
    generation &+= 1
    let submittedGeneration = generation
    activeCredential = nil
    verifiedProfile = nil
    lastSuccessfulVerification = nil
    transition(to: .signedOut)
    await remote.cancelAllRequests()
    await protectedSession.clearProtectedSession()

    do {
      try await credentials.delete(generation: submittedGeneration)
      guard generation == submittedGeneration else { return .signedOut }
      await credentials.clearIncompleteSignOut()
      transition(to: .signedOut)
      return .signedOut
    } catch {
      guard generation == submittedGeneration else { return .incomplete }
      await credentials.markIncompleteSignOut()
      transition(to: .incompleteSignOut)
      return .incomplete
    }
  }

  public func retryIncompleteSignOut() async -> SignOutOutcome {
    guard currentState == .incompleteSignOut else {
      return currentState == .signedOut ? .signedOut : .incomplete
    }
    return await signOut()
  }

  private func verify(_ storedToken: StoredAccessToken, generation submittedGeneration: UInt64) async {
    let token: AccessToken
    let boundProfileID: Anime365ProfileID?
    switch storedToken {
    case .pending(let pendingToken):
      token = pendingToken
      boundProfileID = nil
    case .bound(let boundToken, let profileID):
      token = boundToken
      boundProfileID = profileID
    }

    let verification: Anime365ProfileVerification
    do {
      verification = try await remote.profile(using: token)
    } catch AuthenticationRemoteFailure.invalidAccessToken {
      guard generation == submittedGeneration else { return }
      await discardInvalidCredential(generation: submittedGeneration)
      return
    } catch {
      guard generation == submittedGeneration else { return }
      if let boundProfileID {
        let profile = if let verifiedProfile, verifiedProfile.id == boundProfileID {
          verifiedProfile
        } else {
          Anime365Profile(id: boundProfileID)
        }
        transition(
          to: .authenticatedProfile(
            profile,
            eligibility: .unknown
          )
        )
      } else {
        transition(to: .verifying)
      }
      return
    }

    guard generation == submittedGeneration else { return }
    guard boundProfileID == nil || boundProfileID == verification.profile.id else {
      await discardInvalidCredential(generation: submittedGeneration)
      return
    }
    do {
      try await credentials.bind(
        token,
        to: verification.profile.id,
        generation: submittedGeneration
      )
    } catch {
      guard generation == submittedGeneration else { return }
      transition(to: .credentialUnavailable)
      return
    }
    guard generation == submittedGeneration else { return }
    activeCredential = .bound(token, profileID: verification.profile.id)
    verifiedProfile = verification.profile
    lastSuccessfulVerification = now()
    switch verification.eligibility {
    case .active:
      transition(to: .subscriber(verification.profile))
    case .unknown, .inactive:
      transition(
        to: .authenticatedProfile(
          verification.profile,
          eligibility: verification.eligibility
        )
      )
    }
  }

  private func discardInvalidCredential(generation submittedGeneration: UInt64) async {
    activeCredential = nil
    verifiedProfile = nil
    lastSuccessfulVerification = nil
    do {
      try await credentials.delete(generation: submittedGeneration)
      guard generation == submittedGeneration else { return }
      await credentials.clearIncompleteSignOut()
      transition(to: .signedOut)
    } catch {
      guard generation == submittedGeneration else { return }
      await credentials.markIncompleteSignOut()
      transition(to: .incompleteSignOut)
    }
  }

  private func transition(to state: AuthenticationState) {
    currentState = state
    for observer in observers.values { observer.yield(state) }
  }

  private func removeObserver(_ observerID: UInt64) {
    observers[observerID] = nil
  }
}

private extension StoredAccessToken {
  var token: AccessToken {
    switch self {
    case .pending(let token), .bound(let token, _): token
    }
  }
}
