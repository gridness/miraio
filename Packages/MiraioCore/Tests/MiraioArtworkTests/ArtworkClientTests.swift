import Foundation
import Testing

import MiraioApplication
import MiraioArtwork

@Suite("Safe public artwork loading")
struct ArtworkClientTests {
  @Test("artwork transport has its own bounded public cache and no cookies")
  func usesPublicArtworkNetworkPurpose() {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let configuration = URLSessionArtworkTransport.makeConfiguration(
      cacheDirectoryURL: directory
    )

    #expect(configuration.urlCache?.memoryCapacity == 32 * 1_024 * 1_024)
    #expect(configuration.urlCache?.diskCapacity == 512 * 1_024 * 1_024)
    #expect(configuration.httpCookieAcceptPolicy == .never)
    #expect(configuration.httpShouldSetCookies == false)
    #expect(configuration.httpMaximumConnectionsPerHost == 4)
  }

  @Test("non-HTTPS and credential-bearing locations are rejected before transport")
  func rejectsUnsafeLocations() async throws {
    let transport = ArtworkTransportSpy()
    let client = ArtworkClient(transport: transport)
    let insecure = try #require(
      ArtworkRequest(
        url: URL(string: "http://images.example.test/poster.jpg")!,
        pixelWidth: 300,
        pixelHeight: 450,
        scale: 2
      )
    )
    let credentialed = try #require(
      ArtworkRequest(
        url: URL(string: "https://name:secret@images.example.test/poster.jpg")!,
        pixelWidth: 300,
        pixelHeight: 450,
        scale: 2
      )
    )

    await #expect(throws: ArtworkFailure.insecureLocation) {
      try await client.image(for: insecure)
    }
    await #expect(throws: ArtworkFailure.insecureLocation) {
      try await client.image(for: credentialed)
    }
    #expect(await transport.requestCount == 0)
  }

  @Test("identical artwork downloads and decodes coalesce")
  func coalescesDownloadAndDecode() async throws {
    let url = try #require(URL(string: "https://images.example.test/poster.png"))
    let png = try #require(
      Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
      )
    )
    let transport = BlockingArtworkTransport(
      response: ArtworkResponse(data: png, mimeType: "image/png", finalURL: url)
    )
    let client = ArtworkClient(transport: transport)
    let request = try #require(
      ArtworkRequest(url: url, pixelWidth: 300, pixelHeight: 450, scale: 2)
    )

    async let first = client.image(for: request)
    await transport.waitUntilRequested()
    async let second = client.image(for: request)
    for _ in 0..<20 { await Task.yield() }

    #expect(await transport.requestCount == 1)
    await transport.resume()
    let images = try await [first, second]
    #expect(images.allSatisfy { $0.cgImage.width == 1 && $0.cgImage.height == 1 })
  }
}

private actor ArtworkTransportSpy: ArtworkTransport {
  private(set) var requestCount = 0

  func data(for url: URL) async throws -> ArtworkResponse {
    requestCount += 1
    throw ArtworkFailure.transportUnavailable
  }

  func cancelAll() {}
}

private actor BlockingArtworkTransport: ArtworkTransport {
  private(set) var requestCount = 0
  private let response: ArtworkResponse
  private var observer: CheckedContinuation<Void, Never>?
  private var continuations: [CheckedContinuation<ArtworkResponse, any Error>] = []

  init(response: ArtworkResponse) {
    self.response = response
  }

  func data(for url: URL) async throws -> ArtworkResponse {
    requestCount += 1
    observer?.resume()
    observer = nil
    return try await withCheckedThrowingContinuation { continuation in
      continuations.append(continuation)
    }
  }

  func waitUntilRequested() async {
    guard requestCount == 0 else { return }
    await withCheckedContinuation { continuation in
      observer = continuation
    }
  }

  func resume() {
    let pending = continuations
    continuations.removeAll()
    for continuation in pending {
      continuation.resume(returning: response)
    }
  }

  func cancelAll() {
    let pending = continuations
    continuations.removeAll()
    for continuation in pending {
      continuation.resume(throwing: CancellationError())
    }
  }
}
