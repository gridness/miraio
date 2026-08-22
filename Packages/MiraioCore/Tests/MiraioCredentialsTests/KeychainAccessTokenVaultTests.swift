import Foundation
import MiraioApplication
import MiraioCredentials
import MiraioDomain
import Security
import Testing

@Suite("Private Access Token Keychain", .serialized)
struct KeychainAccessTokenVaultTests {
  @Test("one non-synchronizing device-only item binds the Access Token to its verified Profile")
  func storesProfileBoundTokenWithPrivateAttributes() async throws {
    let suffix = UUID().uuidString
    let service = "io.github.gridness.miraio.tests.\(suffix)"
    let defaultsName = "io.github.gridness.miraio.tests.defaults.\(suffix)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    let vault = KeychainAccessTokenVault(
      service: service,
      defaults: defaults,
      useDataProtectionKeychain: false
    )
    try? await vault.delete(generation: 1)
    let token = try #require(AccessToken("synthetic-secret"))
    let profileID = try #require(Anime365ProfileID(42))

    try await vault.storePending(token, generation: 2)
    try await vault.bind(token, to: profileID, generation: 2)

    let storedToken = try await vault.load()
    #expect(storedToken == .bound(token, profileID: profileID))
    let items = try keychainItems(service: service, useDataProtectionKeychain: false)
    let item = try #require(items.first)
    #expect(item[kSecAttrAccount as String] as? String == "profile:42")
    #expect(item[kSecValueData as String] as? Data == Data("synthetic-secret".utf8))

    try await vault.delete(generation: 3)
  }

  @Test("production storage selects the data-protection Keychain")
  func usesDataProtectionKeychainByDefault() async {
    let vault = KeychainAccessTokenVault()
    #expect(await vault.usesDataProtectionKeychain)
    #expect(await vault.usesWhenUnlockedThisDeviceOnly)
    #expect(await vault.synchronizesCredentials == false)
  }

  @Test("incomplete sign-out survives relaunch until retry succeeds")
  func persistsIncompleteSignOutMarker() async throws {
    let suffix = UUID().uuidString
    let service = "io.github.gridness.miraio.tests.marker.\(suffix)"
    let defaultsName = "io.github.gridness.miraio.tests.marker-defaults.\(suffix)"
    let firstDefaults = try #require(UserDefaults(suiteName: defaultsName))
    let firstLaunch = KeychainAccessTokenVault(
      service: service,
      defaults: firstDefaults,
      useDataProtectionKeychain: false
    )
    await firstLaunch.markIncompleteSignOut()

    let reloadedDefaults = try #require(UserDefaults(suiteName: defaultsName))
    let relaunched = KeychainAccessTokenVault(
      service: service,
      defaults: reloadedDefaults,
      useDataProtectionKeychain: false
    )
    #expect(await relaunched.hasIncompleteSignOut())

    await relaunched.clearIncompleteSignOut()
    #expect(await relaunched.hasIncompleteSignOut() == false)
  }

  private func keychainItems(
    service: String,
    useDataProtectionKeychain: Bool
  ) throws -> [[String: Any]] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecReturnAttributes as String: true,
      kSecReturnData as String: true,
      kSecAttrSynchronizable as String: false,
    ]
    if useDataProtectionKeychain {
      query[kSecUseDataProtectionKeychain as String] = true
    }
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess else { throw KeychainTestFailure(status: status) }
    if let items = result as? [[String: Any]] { return items }
    if let item = result as? [String: Any] { return [item] }
    return []
  }
}

private struct KeychainTestFailure: Error {
  let status: OSStatus
}
