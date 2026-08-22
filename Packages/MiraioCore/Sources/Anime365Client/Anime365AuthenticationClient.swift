import Foundation
import MiraioApplication
import MiraioDomain

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct Anime365AuthenticationClient: Anime365AuthenticationRemote, Sendable {
  private let baseURL: URL
  private let appIdentifier: String
  private let userAgent: String
  private let session: URLSession

  public init(
    baseURL: URL = URL(string: "https://smotret-anime.app/api/")!,
    appIdentifier: String,
    userAgent: String,
    session: URLSession? = nil
  ) {
    self.baseURL = baseURL
    self.appIdentifier = appIdentifier
    self.userAgent = userAgent
    self.session = session ?? Self.makeEphemeralSession()
  }

  public func signIn(email: String, password: String) async throws -> AccessToken {
    let data = try await request(
      path: "login",
      queryItems: [
        URLQueryItem(name: "app", value: appIdentifier),
        URLQueryItem(name: "email", value: email),
        URLQueryItem(name: "password", value: password),
      ],
      rejection: .rejectedSignIn
    )
    guard let envelope = try? JSONDecoder().decode(AccessTokenEnvelope.self, from: data),
      let rawValue = envelope.data?.accessToken,
      let token = AccessToken(rawValue)
    else {
      throw AuthenticationRemoteFailure.unusableResponse
    }
    return token
  }

  public func profile(using token: AccessToken) async throws -> Anime365ProfileVerification {
    let data = try await request(
      path: "me",
      queryItems: [URLQueryItem(name: "access_token", value: token.rawValue)],
      rejection: .invalidAccessToken
    )
    guard let envelope = try? JSONDecoder().decode(ProfileEnvelope.self, from: data),
      let payload = envelope.data,
      let isLoggedIn = payload.isLoggedIn
    else {
      throw AuthenticationRemoteFailure.unusableResponse
    }
    guard isLoggedIn else { throw AuthenticationRemoteFailure.invalidAccessToken }
    guard let rawProfileID = payload.id,
      let profileID = Anime365ProfileID(rawProfileID),
      let isPremium = payload.isPremium
    else {
      throw AuthenticationRemoteFailure.unusableResponse
    }
    let displayName = payload.name?.trimmingCharacters(in: .whitespacesAndNewlines)
    return Anime365ProfileVerification(
      profile: Anime365Profile(
        id: profileID,
        displayName: displayName?.isEmpty == false ? displayName : nil
      ),
      eligibility: isPremium ? .active : .inactive
    )
  }

  public func cancelAllRequests() async {
    let tasks = await session.allTasks
    for task in tasks { task.cancel() }
  }

  private func request(
    path: String,
    queryItems: [URLQueryItem],
    rejection: AuthenticationRemoteFailure
  ) async throws -> Data {
    var components = URLComponents(
      url: baseURL.appending(path: path),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = queryItems
    guard let url = components?.url else {
      throw AuthenticationRemoteFailure.unusableResponse
    }
    var request = URLRequest(url: url)
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.cachePolicy = .reloadIgnoringLocalCacheData

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw AuthenticationRemoteFailure.unavailable
    }
    guard let response = response as? HTTPURLResponse else {
      throw AuthenticationRemoteFailure.unusableResponse
    }
    if let providerError = try? JSONDecoder().decode(AuthenticationErrorEnvelope.self, from: data),
      providerError.error != nil
    {
      throw providerError.error?.code == 403 ? rejection : .serviceRejected
    }
    guard (200..<300).contains(response.statusCode) else {
      throw response.statusCode == 403 ? rejection : .serviceRejected
    }
    return data
  }

  package static func makeEphemeralSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieAcceptPolicy = .never
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.httpMaximumConnectionsPerHost = 2
    return URLSession(configuration: configuration)
  }
}

private struct AccessTokenEnvelope: Decodable {
  struct Payload: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
    }
  }

  let data: Payload?
}

private struct AuthenticationErrorEnvelope: Decodable {
  struct ProviderError: Decodable {
    let code: Int
  }

  let error: ProviderError?
}

private struct ProfileEnvelope: Decodable {
  struct Payload: Decodable {
    let isLoggedIn: Bool?
    let id: Int?
    let name: String?
    let isPremium: Bool?

    enum CodingKeys: String, CodingKey {
      case isLoggedIn = "isLogined"
      case id
      case name
      case isPremium
    }
  }

  let data: Payload?
}
