import Foundation
import MiraioApplication
import Observation

enum AuthenticationNotice: Equatable {
  case rejectedSignIn
  case serviceUnavailable
  case verificationUnavailable
  case credentialUnavailable
  case incompleteSignOut

  var message: String {
    switch self {
    case .rejectedSignIn:
      String(localized: "Anime365 did not accept these sign-in details.")
    case .serviceUnavailable:
      String(localized: "Miraio couldn’t reach Anime365. Your password was cleared. Try again.")
    case .verificationUnavailable:
      String(localized: "Your Access Token was preserved, but Subscription Eligibility could not be verified. Retry when Anime365 is available.")
    case .credentialUnavailable:
      String(localized: "The private Access Token could not be accessed. Public Catalogue and Watch History remain available.")
    case .incompleteSignOut:
      String(localized: "Protected access is disabled, but the Access Token could not be deleted. Retry sign-out.")
    }
  }
}

@MainActor
@Observable
final class AuthenticationViewModel {
  var state: AuthenticationState = .verifying
  var email = ""
  var password = ""
  var notice: AuthenticationNotice?
  var isSignInPresented = false
  var isPerformingAction = false

  private let authority: AuthenticationAuthority
  private let fixtureState: AuthenticationState?

  init(
    authority: AuthenticationAuthority,
    fixtureState: AuthenticationState? = nil
  ) {
    self.authority = authority
    self.fixtureState = fixtureState
    if let fixtureState { state = fixtureState }
  }

  func observe() async {
    if let fixtureState {
      state = fixtureState
      return
    }
    let states = await authority.states()
    state = await authority.currentState
    await authority.restore()
    for await state in states {
      guard !Task.isCancelled else { return }
      self.state = state
    }
  }

  func presentSignIn() {
    guard state == .signedOut, !isPerformingAction else { return }
    notice = nil
    isSignInPresented = true
  }

  func dismissSignIn() {
    email = ""
    password = ""
    notice = nil
    isSignInPresented = false
  }

  func submitSignIn() async {
    await performAction {
      let submittedEmail = email
      let submittedPassword = password
      password = ""

      let outcome = await authority.signIn(
        email: submittedEmail,
        password: submittedPassword
      )
      switch outcome {
      case .authenticated:
        email = ""
        notice = nil
        isSignInPresented = false
      case .rejected:
        notice = .rejectedSignIn
      case .verificationUnavailable:
        email = ""
        notice = .verificationUnavailable
        isSignInPresented = false
      case .credentialUnavailable:
        email = ""
        notice = .credentialUnavailable
        isSignInPresented = false
      case .unavailable:
        notice = .serviceUnavailable
      case .blocked:
        dismissSignIn()
      }
    }
  }

  func refreshEligibility() async {
    await performAction { await authority.refreshEligibility() }
  }

  func retryCredentialAccess() async {
    await performAction { await authority.restore() }
  }

  func signOut() async {
    await performAction {
      email = ""
      password = ""
      notice = await authority.signOut() == .incomplete ? .incompleteSignOut : nil
    }
  }

  func retryIncompleteSignOut() async {
    await performAction {
      notice = await authority.retryIncompleteSignOut() == .incomplete
        ? .incompleteSignOut
        : nil
    }
  }

  private func performAction(_ action: () async -> Void) async {
    guard !isPerformingAction else { return }
    isPerformingAction = true
    defer { isPerformingAction = false }
    await action()
  }
}
