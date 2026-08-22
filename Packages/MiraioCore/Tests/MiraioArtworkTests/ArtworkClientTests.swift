import Foundation
import ImageIO
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
    #expect(configuration.urlCredentialStorage == nil)
    #expect(configuration.httpMaximumConnectionsPerHost == 4)
  }

  @Test("alternative private address forms are rejected before transport")
  func rejectsAlternativePrivateAddressForms() throws {
    let privateLocations = try [
      "https://localhost./poster.png",
      "https://127.1/poster.png",
      "https://2130706433/poster.png",
      "https://[::ffff:127.0.0.1]/poster.png",
    ].map { try #require(URL(string: $0)) }

    #expect(privateLocations.allSatisfy { !ArtworkLocationPolicy.hasAllowedSyntax($0) })
    #expect(!ArtworkLocationPolicy.resolvesOnlyToPublicAddresses("127.0.0.1"))
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
    _ = try await client.image(for: request)
    #expect(await transport.requestCount == 1)
  }

  @Test("distinct artwork downloads never exceed four concurrent transfers")
  func boundsConcurrentDownloads() async throws {
    let firstURL = try #require(URL(string: "https://images.example.test/0.png"))
    let png = try #require(
      Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
      )
    )
    let transport = BlockingArtworkTransport(
      response: ArtworkResponse(data: png, mimeType: "image/png", finalURL: firstURL)
    )
    let client = ArtworkClient(transport: transport)
    let requests = try (0..<5).map { index in
      try #require(
        ArtworkRequest(
          url: URL(string: "https://images.example.test/\(index).png")!,
          pixelWidth: 300,
          pixelHeight: 450,
          scale: 2
        )
      )
    }

    let loads = requests.map { request in
      Task { try await client.image(for: request) }
    }
    await transport.waitUntilRequestCountIsAtLeast(4)
    for _ in 0..<20 { await Task.yield() }

    #expect(await transport.requestCount == 4)
    await transport.resume()
    await transport.waitUntilRequestCountIsAtLeast(5)
    await transport.resume()
    for load in loads { _ = try await load.value }
  }

  @Test("distinct artwork decodes never exceed two concurrent operations")
  func boundsConcurrentDecodes() async throws {
    let firstURL = try #require(URL(string: "https://images.example.test/0.png"))
    let transport = StaticArtworkTransport(
      response: ArtworkResponse(data: Data([0]), mimeType: "image/png", finalURL: firstURL)
    )
    let decoder = BlockingArtworkDecoder(image: try onePixelArtworkImage())
    let client = ArtworkClient(transport: transport, decoder: decoder)
    let requests = try (0..<3).map { index in
      try #require(
        ArtworkRequest(
          url: URL(string: "https://images.example.test/\(index).png")!,
          pixelWidth: 300,
          pixelHeight: 450,
          scale: 2
        )
      )
    }

    let loads = requests.map { request in Task { try await client.image(for: request) } }
    await decoder.waitUntilRequestCountIsAtLeast(2)
    for _ in 0..<20 { await Task.yield() }

    #expect(await decoder.requestCount == 2)
    #expect(await decoder.maximumConcurrentRequestCount == 2)
    await decoder.resumeAll()
    await decoder.waitUntilRequestCountIsAtLeast(3)
    await decoder.resumeAll()
    for load in loads { _ = try await load.value }
  }

  @Test("prefetch loads exactly the caller-selected requests")
  func prefetchesSelectedRequests() async throws {
    let firstURL = try #require(URL(string: "https://images.example.test/0.png"))
    let png = try #require(
      Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
      )
    )
    let transport = StaticArtworkTransport(
      response: ArtworkResponse(data: png, mimeType: "image/png", finalURL: firstURL)
    )
    let client = ArtworkClient(transport: transport)
    let requests = try (0..<8).map { index in
      try #require(
        ArtworkRequest(
          url: URL(string: "https://images.example.test/\(index).png")!,
          pixelWidth: 180,
          pixelHeight: 250,
          scale: 2
        )
      )
    }

    await client.prefetch(requests)

    #expect(await transport.requestCount == 8)
  }

  @Test("a redirect result that resolves to a private address is rejected")
  func rejectsPrivateRedirectResult() async throws {
    let requestedURL = try #require(URL(string: "https://images.example.test/poster.png"))
    let privateURL = try #require(URL(string: "https://127.0.0.1/poster.png"))
    let transport = StaticArtworkTransport(
      response: ArtworkResponse(data: Data(), mimeType: "image/png", finalURL: privateURL)
    )
    let client = ArtworkClient(transport: transport)
    let request = try #require(
      ArtworkRequest(url: requestedURL, pixelWidth: 300, pixelHeight: 450, scale: 2)
    )

    await #expect(throws: ArtworkFailure.insecureLocation) {
      try await client.image(for: request)
    }
  }

  @Test("abandoning the only artwork caller cancels its shared work")
  func cancelsAbandonedArtworkWork() async throws {
    let url = try #require(URL(string: "https://images.example.test/poster.png"))
    let transport = CancellationAwareArtworkTransport()
    let client = ArtworkClient(transport: transport)
    let request = try #require(
      ArtworkRequest(url: url, pixelWidth: 300, pixelHeight: 450, scale: 2)
    )

    let loading = Task { try await client.image(for: request) }
    await transport.waitUntilRequested()
    loading.cancel()
    for _ in 0..<30 { await Task.yield() }

    #expect(await transport.wasCancelled)
    await client.cancelNonessentialWork()
    _ = try? await loading.value
  }

  @Test("abandoning the only caller also cancels in-progress decode work")
  func cancelsAbandonedArtworkDecode() async throws {
    let url = try #require(URL(string: "https://images.example.test/poster.png"))
    let transport = StaticArtworkTransport(
      response: ArtworkResponse(data: Data([0]), mimeType: "image/png", finalURL: url)
    )
    let decoder = CancellationAwareArtworkDecoder()
    let client = ArtworkClient(transport: transport, decoder: decoder)
    let request = try #require(
      ArtworkRequest(url: url, pixelWidth: 300, pixelHeight: 450, scale: 2)
    )

    let loading = Task { try await client.image(for: request) }
    await decoder.waitUntilRequested()
    loading.cancel()
    for _ in 0..<30 { await Task.yield() }

    #expect(await decoder.wasCancelled)
    _ = try? await loading.value
  }

  @Test("an oversized artwork body is rejected before decode")
  func rejectsOversizedArtworkBody() async throws {
    let url = try #require(URL(string: "https://images.example.test/poster.png"))
    let transport = StaticArtworkTransport(
      response: ArtworkResponse(
        data: Data(count: 20 * 1_024 * 1_024 + 1),
        mimeType: "image/png",
        finalURL: url
      )
    )
    let client = ArtworkClient(transport: transport)
    let request = try #require(
      ArtworkRequest(url: url, pixelWidth: 300, pixelHeight: 450, scale: 2)
    )

    await #expect(throws: ArtworkFailure.oversizedDownload) {
      try await client.image(for: request)
    }
  }

  @Test("source image dimensions are capped at 40 megapixels")
  func capsSourceImageDimensions() throws {
    try ArtworkClient.validatePixelDimensions(width: 8_000, height: 5_000)
    #expect(throws: ArtworkFailure.oversizedImage) {
      try ArtworkClient.validatePixelDimensions(width: 8_001, height: 5_000)
    }
  }

  @Test("the production ImageIO decoder executes off the main thread")
  @MainActor
  func decodesOffMainThread() async throws {
    let executionRecorder = ThreadExecutionRecorder()
    let decoder = ImageIOArtworkDecoder { isMainThread in
      executionRecorder.record(isMainThread)
    }
    let url = try #require(URL(string: "https://images.example.test/poster.png"))
    let request = try #require(
      ArtworkRequest(url: url, pixelWidth: 300, pixelHeight: 450, scale: 2)
    )
    let png = try #require(
      Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
      )
    )

    let image = try await decoder.decode(png, for: request)

    #expect(image.cgImage.width == 1)
    #expect(executionRecorder.values == [false])
  }

  @Test("decoded image LRU obeys the 128 MiB production cap")
  func evictsLeastRecentlyUsedDecodedImage() async throws {
    let firstURL = try #require(URL(string: "https://images.example.test/0.png"))
    let image = try onePixelArtworkImage()
    let oneImageCost = image.cgImage.bytesPerRow * image.cgImage.height
    let transport = StaticArtworkTransport(
      response: ArtworkResponse(data: Data([0]), mimeType: "image/png", finalURL: firstURL)
    )
    let client = ArtworkClient(
      transport: transport,
      decoder: StaticArtworkDecoder(image: image),
      decodedCapacity: oneImageCost * 2
    )
    let requests = try (0..<3).map { index in
      try #require(
        ArtworkRequest(
          url: URL(string: "https://images.example.test/\(index).png")!,
          pixelWidth: 180,
          pixelHeight: 250,
          scale: 2
        )
      )
    }

    for request in requests { _ = try await client.image(for: request) }
    _ = try await client.image(for: requests[0])

    #expect(ArtworkClient.decodedImageCapacityBytes == 128 * 1_024 * 1_024)
    #expect(await transport.requestCount == 4)
  }

  @Test("redirect policy allows five public hops and rejects the sixth or a private hop")
  func capsAndValidatesRedirects() throws {
    let delegate = ArtworkRedirectDelegate()
    let publicURL = try #require(URL(string: "https://93.184.216.34/poster.png"))
    let privateURL = try #require(URL(string: "https://127.0.0.1/poster.png"))

    for _ in 0..<5 {
      #expect(delegate.shouldFollowRedirect(taskIdentifier: 1, url: publicURL))
    }
    #expect(!delegate.shouldFollowRedirect(taskIdentifier: 1, url: publicURL))
    #expect(!delegate.shouldFollowRedirect(taskIdentifier: 2, url: privateURL))
    delegate.completed(taskIdentifier: 1)
    #expect(delegate.shouldFollowRedirect(taskIdentifier: 1, url: publicURL))
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
  private var observers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
  private var continuations: [CheckedContinuation<ArtworkResponse, any Error>] = []

  init(response: ArtworkResponse) {
    self.response = response
  }

  func data(for url: URL) async throws -> ArtworkResponse {
    requestCount += 1
    resumeSatisfiedObservers()
    return try await withCheckedThrowingContinuation { continuation in
      continuations.append(continuation)
    }
  }

  func waitUntilRequested() async {
    await waitUntilRequestCountIsAtLeast(1)
  }

  func waitUntilRequestCountIsAtLeast(_ count: Int) async {
    guard requestCount < count else { return }
    await withCheckedContinuation { continuation in observers.append((count, continuation)) }
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

  private func resumeSatisfiedObservers() {
    let satisfied = observers.filter { requestCount >= $0.count }
    observers.removeAll { requestCount >= $0.count }
    for observer in satisfied { observer.continuation.resume() }
  }
}

private actor CancellationAwareArtworkTransport: ArtworkTransport {
  private(set) var wasCancelled = false
  private var observer: CheckedContinuation<Void, Never>?
  private var didStart = false

  func data(for url: URL) async throws -> ArtworkResponse {
    didStart = true
    observer?.resume()
    observer = nil
    do {
      try await Task.sleep(for: .seconds(60))
      throw ArtworkFailure.transportUnavailable
    } catch is CancellationError {
      wasCancelled = true
      throw ArtworkFailure.cancelled
    }
  }

  func waitUntilRequested() async {
    guard !didStart else { return }
    await withCheckedContinuation { continuation in observer = continuation }
  }

  func cancelAll() {
    wasCancelled = true
  }
}

private actor StaticArtworkTransport: ArtworkTransport {
  let response: ArtworkResponse
  private(set) var requestCount = 0

  init(response: ArtworkResponse) {
    self.response = response
  }

  func data(for url: URL) -> ArtworkResponse {
    requestCount += 1
    return response
  }
  func cancelAll() {}
}

private actor BlockingArtworkDecoder: ArtworkDecoding {
  private(set) var requestCount = 0
  private(set) var maximumConcurrentRequestCount = 0
  private var concurrentRequestCount = 0
  private let image: ArtworkImage
  private var observers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
  private var continuations: [CheckedContinuation<ArtworkImage, any Error>] = []

  init(image: ArtworkImage) {
    self.image = image
  }

  func decode(_ data: Data, for request: ArtworkRequest) async throws -> ArtworkImage {
    requestCount += 1
    concurrentRequestCount += 1
    maximumConcurrentRequestCount = max(maximumConcurrentRequestCount, concurrentRequestCount)
    let satisfied = observers.filter { requestCount >= $0.count }
    observers.removeAll { requestCount >= $0.count }
    for observer in satisfied { observer.continuation.resume() }
    let image = try await withCheckedThrowingContinuation { continuation in
      continuations.append(continuation)
    }
    concurrentRequestCount -= 1
    return image
  }

  func waitUntilRequestCountIsAtLeast(_ count: Int) async {
    guard requestCount < count else { return }
    await withCheckedContinuation { continuation in
      observers.append((count, continuation))
    }
  }

  func resumeAll() {
    let pending = continuations
    continuations.removeAll()
    for continuation in pending { continuation.resume(returning: image) }
  }
}

private struct StaticArtworkDecoder: ArtworkDecoding {
  let image: ArtworkImage

  func decode(_ data: Data, for request: ArtworkRequest) -> ArtworkImage {
    image
  }
}

private actor CancellationAwareArtworkDecoder: ArtworkDecoding {
  private(set) var wasCancelled = false
  private var observer: CheckedContinuation<Void, Never>?
  private var didStart = false

  func decode(_ data: Data, for request: ArtworkRequest) async throws -> ArtworkImage {
    didStart = true
    observer?.resume()
    observer = nil
    do {
      try await Task.sleep(for: .seconds(60))
      throw ArtworkFailure.malformedImage
    } catch is CancellationError {
      wasCancelled = true
      throw ArtworkFailure.cancelled
    }
  }

  func waitUntilRequested() async {
    guard !didStart else { return }
    await withCheckedContinuation { continuation in observer = continuation }
  }
}

private func onePixelArtworkImage() throws -> ArtworkImage {
  let png = try #require(
    Data(
      base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )
  )
  let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
  return ArtworkImage(cgImage: try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
}

private final class ThreadExecutionRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [Bool] = []

  var values: [Bool] {
    lock.withLock { storage }
  }

  func record(_ isMainThread: Bool) {
    lock.withLock { storage.append(isMainThread) }
  }
}
