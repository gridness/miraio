import Foundation
import MiraioApplication
import MiraioDomain
import Security

public actor KeychainAccessTokenVault: AccessTokenVault {
  private let service: String
  private let defaults: UserDefaults
  private let incompleteSignOutKey: String
  package let usesDataProtectionKeychain: Bool
  package let usesWhenUnlockedThisDeviceOnly = true
  package let synchronizesCredentials = false
  private var latestMutationGeneration: UInt64 = 0

  public init(
    service: String = "io.github.gridness.miraio.anime365.access-token",
    defaults: UserDefaults = .standard,
    useDataProtectionKeychain: Bool = true
  ) {
    self.service = service
    self.defaults = defaults
    usesDataProtectionKeychain = useDataProtectionKeychain
    incompleteSignOutKey = "\(service).incomplete-sign-out"
  }

  public func load() throws -> StoredAccessToken? {
    var query = baseQuery
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnAttributes as String] = true
    query[kSecReturnData as String] = true

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess,
      let item = result as? [String: Any],
      let data = item[kSecValueData as String] as? Data,
      let rawValue = String(data: data, encoding: .utf8),
      let token = AccessToken(rawValue),
      let account = item[kSecAttrAccount as String] as? String
    else {
      throw CredentialVaultFailure(status: status)
    }

    if account == "pending" { return .pending(token) }
    guard account.hasPrefix("profile:"),
      let rawProfileID = Int(account.dropFirst("profile:".count)),
      let profileID = Anime365ProfileID(rawProfileID)
    else {
      throw CredentialVaultFailure(status: errSecDecode)
    }
    return .bound(token, profileID: profileID)
  }

  public func storePending(_ token: AccessToken, generation: UInt64) throws {
    try acceptMutation(generation)
    try deleteExistingItem()
    var item = baseQuery
    item[kSecAttrAccount as String] = "pending"
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    item[kSecValueData as String] = Data(token.rawValue.utf8)
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { throw CredentialVaultFailure(status: status) }
  }

  public func bind(
    _ token: AccessToken,
    to profileID: Anime365ProfileID,
    generation: UInt64
  ) throws {
    try acceptMutation(generation)
    let updates: [String: Any] = [
      kSecAttrAccount as String: "profile:\(profileID.rawValue)",
      kSecValueData as String: Data(token.rawValue.utf8),
    ]
    let status = SecItemUpdate(baseQuery as CFDictionary, updates as CFDictionary)
    guard status == errSecSuccess else { throw CredentialVaultFailure(status: status) }
  }

  public func delete(generation: UInt64) throws {
    try acceptMutation(generation)
    try deleteExistingItem()
  }

  public func hasIncompleteSignOut() -> Bool {
    defaults.bool(forKey: incompleteSignOutKey)
  }

  public func markIncompleteSignOut() {
    defaults.set(true, forKey: incompleteSignOutKey)
  }

  public func clearIncompleteSignOut() {
    defaults.removeObject(forKey: incompleteSignOutKey)
  }

  private var baseQuery: [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrSynchronizable as String: false,
    ]
    if usesDataProtectionKeychain {
      query[kSecUseDataProtectionKeychain as String] = true
    }
    return query
  }

  private func deleteExistingItem() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw CredentialVaultFailure(status: status)
    }
  }

  private func acceptMutation(_ generation: UInt64) throws {
    guard generation >= latestMutationGeneration else {
      throw ObsoleteCredentialMutation()
    }
    latestMutationGeneration = generation
  }
}

private struct CredentialVaultFailure: Error {
  let status: OSStatus
}

private struct ObsoleteCredentialMutation: Error {}
