import Anime365Client
import Foundation
import MiraioApplication
import MiraioDomain
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite("Official Anime365 Profile authentication", .serialized)
struct Anime365AuthenticationClientTests {
  @Test("documented sign-in maps only the issued Access Token")
  func signsInThroughDocumentedExchange() async throws {
    let session = makeSession()
    AuthenticationURLProtocol.handler = { request in
      let requestURL = try #require(request.url)
      let components = try #require(
        URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
      )
      let query = Dictionary(
        uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
      )
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path == "/api/login")
      #expect(query["app"] == "public-app-id")
      #expect(query["email"] == "mira@example.com")
      #expect(query["password"] == "test-password")
      #expect(request.value(forHTTPHeaderField: "User-Agent") == "Miraio/1.0")
      return (
        try #require(
          HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
          )
        ),
        Data(#"{"data":{"access_token":"verified-secret"}}"#.utf8)
      )
    }
    let client = Anime365AuthenticationClient(
      baseURL: try #require(URL(string: "https://example.test/api/")),
      appIdentifier: "public-app-id",
      userAgent: "Miraio/1.0",
      session: session
    )

    let token = try await client.signIn(
      email: "mira@example.com",
      password: "test-password"
    )

    #expect(token == AccessToken("verified-secret"))
  }

  @Test("Profile verification maps only identity and three-valued Subscription Eligibility")
  func verifiesSubscriberProfile() async throws {
    let session = makeSession()
    AuthenticationURLProtocol.handler = { request in
      let requestURL = try #require(request.url)
      let components = try #require(
        URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
      )
      let query = Dictionary(
        uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
      )
      #expect(request.url?.path == "/api/me")
      #expect(query == ["access_token": "verified-secret"])
      return (
        try #require(
          HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
          )
        ),
        Data(
          #"{"data":{"isLogined":true,"id":42,"name":"Mira","isPremium":true,"premiumUntil":"opaque"}}"#.utf8
        )
      )
    }
    let client = Anime365AuthenticationClient(
      baseURL: try #require(URL(string: "https://example.test/api/")),
      appIdentifier: "public-app-id",
      userAgent: "Miraio/1.0",
      session: session
    )
    let token = try #require(AccessToken("verified-secret"))

    let verification = try await client.profile(using: token)

    #expect(
      verification
        == Anime365ProfileVerification(
          profile: Anime365Profile(
            id: try #require(Anime365ProfileID(42)),
            displayName: "Mira"
          ),
          eligibility: .active
        )
    )
  }

  @Test("Profile verification maps a non-premium Profile to inactive eligibility")
  func verifiesInactiveProfile() async throws {
    let session = makeSession()
    AuthenticationURLProtocol.handler = { request in
      let requestURL = try #require(request.url)
      return (
        try #require(
          HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
          )
        ),
        Data(#"{"data":{"isLogined":true,"id":42,"name":"Mira","isPremium":false}}"#.utf8)
      )
    }
    let client = Anime365AuthenticationClient(
      baseURL: try #require(URL(string: "https://example.test/api/")),
      appIdentifier: "public-app-id",
      userAgent: "Miraio/1.0",
      session: session
    )
    let token = try #require(AccessToken("verified-secret"))

    let verification = try await client.profile(using: token)

    #expect(verification.eligibility == .inactive)
  }

  @Test("sign-in rejection is categorical even when the provider embeds 403 in HTTP 200")
  func mapsRejectedSignInWithoutProviderMessage() async throws {
    let session = makeSession()
    AuthenticationURLProtocol.handler = { request in
      let requestURL = try #require(request.url)
      return (
        try #require(
          HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
          )
        ),
        Data(#"{"error":{"code":403,"message":"sensitive provider copy"}}"#.utf8)
      )
    }
    let client = Anime365AuthenticationClient(
      baseURL: try #require(URL(string: "https://example.test/api/")),
      appIdentifier: "public-app-id",
      userAgent: "Miraio/1.0",
      session: session
    )

    await #expect(throws: AuthenticationRemoteFailure.rejectedSignIn) {
      _ = try await client.signIn(email: "rejected@example.com", password: "synthetic")
    }
  }

  @Test("a guest Profile response definitively invalidates the Access Token")
  func mapsGuestProfileToInvalidCredential() async throws {
    let session = makeSession()
    AuthenticationURLProtocol.handler = { request in
      let requestURL = try #require(request.url)
      return (
        try #require(
          HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
          )
        ),
        Data(#"{"data":{"isLogined":false}}"#.utf8)
      )
    }
    let client = Anime365AuthenticationClient(
      baseURL: try #require(URL(string: "https://example.test/api/")),
      appIdentifier: "public-app-id",
      userAgent: "Miraio/1.0",
      session: session
    )
    let token = try #require(AccessToken("invalid-token"))

    await #expect(throws: AuthenticationRemoteFailure.invalidAccessToken) {
      _ = try await client.profile(using: token)
    }
  }

  @Test("authenticated traffic uses a cookieless no-cache credentialless transport")
  func usesAuthenticatedNetworkPurpose() {
    let configuration = Anime365AuthenticationClient.makeEphemeralSession().configuration

    #expect(configuration.urlCache == nil)
    #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    #expect(configuration.httpCookieAcceptPolicy == .never)
    #expect(configuration.httpShouldSetCookies == false)
    #expect(configuration.urlCredentialStorage == nil)
  }

  private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AuthenticationURLProtocol.self]
    return URLSession(configuration: configuration)
  }
}

private final class AuthenticationURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.unknown))
      return
    }
    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}
