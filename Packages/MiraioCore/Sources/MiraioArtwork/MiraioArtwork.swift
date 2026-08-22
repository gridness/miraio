import CoreGraphics
import Darwin
import Foundation
import ImageIO
import MiraioApplication

private let maximumArtworkDownloadBytes = 20 * 1_024 * 1_024

package struct ArtworkResponse: Sendable {
  package let data: Data
  package let mimeType: String?
  package let finalURL: URL

  package init(data: Data, mimeType: String?, finalURL: URL) {
    self.data = data
    self.mimeType = mimeType
    self.finalURL = finalURL
  }
}

package protocol ArtworkTransport: Sendable {
  func data(for url: URL) async throws -> ArtworkResponse
  func cancelAll() async
}

package protocol ArtworkDecoding: Sendable {
  func decode(_ data: Data, for request: ArtworkRequest) async throws -> ArtworkImage
}

package struct ImageIOArtworkDecoder: ArtworkDecoding {
  private let executionObserver: @Sendable (Bool) -> Void

  package init(
    executionObserver: @escaping @Sendable (Bool) -> Void = { _ in }
  ) {
    self.executionObserver = executionObserver
  }

  package func decode(_ data: Data, for request: ArtworkRequest) async throws -> ArtworkImage {
    let executionObserver = self.executionObserver
    let decodeTask = Task.detached(priority: .userInitiated) {
      executionObserver(pthread_main_np() != 0)
      return try ArtworkClient.decodeOffMain(data, request: request)
    }
    return try await withTaskCancellationHandler {
      try await decodeTask.value
    } onCancel: {
      decodeTask.cancel()
    }
  }
}

public actor ArtworkClient: ArtworkLoading {
  private struct InFlightDownload: Sendable {
    let id: UUID
    let task: Task<ArtworkResponse, any Error>
    var demandIDs: Set<UUID>
  }

  private struct InFlightDecode: Sendable {
    let id: UUID
    let task: Task<ArtworkImage, any Error>
    var demandIDs: Set<UUID>
  }

  private struct DecodedEntry: @unchecked Sendable {
    let image: ArtworkImage
    let byteCost: Int
    var accessSequence: UInt64
  }

  private static let maximumPixels = 40_000_000
  package nonisolated static let decodedImageCapacityBytes = 128 * 1_024 * 1_024

  private let transport: any ArtworkTransport
  private let decoder: any ArtworkDecoding
  private let decodedCapacity: Int
  private let downloadPermits = AsyncPermitPool(limit: 4)
  private let decodePermits = AsyncPermitPool(limit: 2)
  private var downloads: [URL: InFlightDownload] = [:]
  private var decodes: [ArtworkRequest: InFlightDecode] = [:]
  private var decoded: [ArtworkRequest: DecodedEntry] = [:]
  private var decodedCost = 0
  private var accessSequence: UInt64 = 0

  public init(cacheDirectoryURL: URL) {
    transport = URLSessionArtworkTransport(cacheDirectoryURL: cacheDirectoryURL)
    decoder = ImageIOArtworkDecoder()
    decodedCapacity = Self.decodedImageCapacityBytes
  }

  package init(transport: any ArtworkTransport) {
    self.transport = transport
    decoder = ImageIOArtworkDecoder()
    decodedCapacity = Self.decodedImageCapacityBytes
  }

  package init(
    transport: any ArtworkTransport,
    decoder: any ArtworkDecoding,
    decodedCapacity: Int = ArtworkClient.decodedImageCapacityBytes
  ) {
    self.transport = transport
    self.decoder = decoder
    self.decodedCapacity = max(0, decodedCapacity)
  }

  public func image(for request: ArtworkRequest) async throws -> ArtworkImage {
    guard ArtworkLocationPolicy.hasAllowedSyntax(request.url) else {
      throw ArtworkFailure.insecureLocation
    }
    accessSequence &+= 1
    if var entry = decoded[request] {
      entry.accessSequence = accessSequence
      decoded[request] = entry
      return entry.image
    }
    let demandID = UUID()
    let inFlight: InFlightDecode
    if var existing = decodes[request] {
      existing.demandIDs.insert(demandID)
      decodes[request] = existing
      inFlight = existing
    } else {
      let id = UUID()
      let task = Task { [self] in
        let response = try await download(request.url)
        return try await decode(response: response, for: request)
      }
      inFlight = InFlightDecode(id: id, task: task, demandIDs: [demandID])
      decodes[request] = inFlight
    }

    return try await withTaskCancellationHandler {
      do {
        let image = try await inFlight.task.value
        releaseDecodeDemand(request: request, flightID: inFlight.id, demandID: demandID)
        try Task.checkCancellation()
        insertDecoded(image, for: request)
        return image
      } catch is CancellationError {
        releaseDecodeDemand(request: request, flightID: inFlight.id, demandID: demandID)
        throw ArtworkFailure.cancelled
      } catch let failure as ArtworkFailure {
        releaseDecodeDemand(request: request, flightID: inFlight.id, demandID: demandID)
        throw failure
      } catch {
        releaseDecodeDemand(request: request, flightID: inFlight.id, demandID: demandID)
        throw ArtworkFailure.transportUnavailable
      }
    } onCancel: {
      Task {
        await self.cancelDecodeDemand(
          request: request,
          flightID: inFlight.id,
          demandID: demandID
        )
      }
    }
  }

  public func cancelNonessentialWork() async {
    let downloadTasks = downloads.values.map(\.task)
    let decodeTasks = decodes.values.map(\.task)
    downloads.removeAll(keepingCapacity: true)
    decodes.removeAll(keepingCapacity: true)
    for task in downloadTasks { task.cancel() }
    for task in decodeTasks { task.cancel() }
    await transport.cancelAll()
  }

  public func releaseDecodedImages() {
    decoded.removeAll(keepingCapacity: false)
    decodedCost = 0
  }

  private func download(_ url: URL) async throws -> ArtworkResponse {
    let demandID = UUID()
    let inFlight: InFlightDownload
    if var existing = downloads[url] {
      existing.demandIDs.insert(demandID)
      downloads[url] = existing
      inFlight = existing
    } else {
      let id = UUID()
      let transport = self.transport
      let permits = downloadPermits
      let task = Task {
        try await permits.withPermit {
          try await transport.data(for: url)
        }
      }
      inFlight = InFlightDownload(id: id, task: task, demandIDs: [demandID])
      downloads[url] = inFlight
    }

    return try await withTaskCancellationHandler {
      do {
        let response = try await inFlight.task.value
        releaseDownloadDemand(url: url, flightID: inFlight.id, demandID: demandID)
        try Task.checkCancellation()
        guard ArtworkLocationPolicy.hasAllowedSyntax(response.finalURL) else {
          throw ArtworkFailure.insecureLocation
        }
        guard response.data.count <= maximumArtworkDownloadBytes else {
          throw ArtworkFailure.oversizedDownload
        }
        guard response.mimeType?.lowercased().hasPrefix("image/") == true else {
          throw ArtworkFailure.unsupportedContent
        }
        return response
      } catch {
        releaseDownloadDemand(url: url, flightID: inFlight.id, demandID: demandID)
        throw error
      }
    } onCancel: {
      Task {
        await self.cancelDownloadDemand(
          url: url,
          flightID: inFlight.id,
          demandID: demandID
        )
      }
    }
  }

  private func releaseDecodeDemand(request: ArtworkRequest, flightID: UUID, demandID: UUID) {
    guard var inFlight = decodes[request], inFlight.id == flightID else { return }
    inFlight.demandIDs.remove(demandID)
    decodes[request] = inFlight.demandIDs.isEmpty ? nil : inFlight
  }

  private func cancelDecodeDemand(request: ArtworkRequest, flightID: UUID, demandID: UUID) {
    guard var inFlight = decodes[request], inFlight.id == flightID else { return }
    inFlight.demandIDs.remove(demandID)
    if inFlight.demandIDs.isEmpty {
      decodes[request] = nil
      inFlight.task.cancel()
    } else {
      decodes[request] = inFlight
    }
  }

  private func releaseDownloadDemand(url: URL, flightID: UUID, demandID: UUID) {
    guard var inFlight = downloads[url], inFlight.id == flightID else { return }
    inFlight.demandIDs.remove(demandID)
    downloads[url] = inFlight.demandIDs.isEmpty ? nil : inFlight
  }

  private func cancelDownloadDemand(url: URL, flightID: UUID, demandID: UUID) {
    guard var inFlight = downloads[url], inFlight.id == flightID else { return }
    inFlight.demandIDs.remove(demandID)
    if inFlight.demandIDs.isEmpty {
      downloads[url] = nil
      inFlight.task.cancel()
    } else {
      downloads[url] = inFlight
    }
  }

  private func decode(
    response: ArtworkResponse,
    for request: ArtworkRequest
  ) async throws -> ArtworkImage {
    let permits = decodePermits
    let decoder = self.decoder
    return try await permits.withPermit {
      try await decoder.decode(response.data, for: request)
    }
  }

  fileprivate nonisolated static func decodeOffMain(
    _ data: Data,
    request: ArtworkRequest
  ) throws -> ArtworkImage {
    try Task.checkCancellation()
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0,
      height > 0
    else { throw ArtworkFailure.malformedImage }
    try validatePixelDimensions(width: width, height: height)
    try Task.checkCancellation()

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(request.pixelWidth, request.pixelHeight),
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { throw ArtworkFailure.malformedImage }
    try Task.checkCancellation()
    return ArtworkImage(cgImage: image)
  }

  package nonisolated static func validatePixelDimensions(
    width: Int,
    height: Int
  ) throws {
    guard width > 0, height > 0, width <= maximumPixels / height else {
      throw ArtworkFailure.oversizedImage
    }
  }

  private func insertDecoded(_ image: ArtworkImage, for request: ArtworkRequest) {
    let bytesPerRow = image.cgImage.bytesPerRow
    guard image.cgImage.height <= decodedCapacity / max(1, bytesPerRow) else { return }
    let cost = bytesPerRow * image.cgImage.height
    accessSequence &+= 1
    if let existing = decoded[request] { decodedCost -= existing.byteCost }
    decoded[request] = DecodedEntry(
      image: image,
      byteCost: cost,
      accessSequence: accessSequence
    )
    decodedCost += cost
    while decodedCost > decodedCapacity,
      let oldest = decoded.min(by: {
        $0.value.accessSequence < $1.value.accessSequence
      })
    {
      decodedCost -= oldest.value.byteCost
      decoded[oldest.key] = nil
    }
  }

}

package enum ArtworkLocationPolicy {
  package static func hasAllowedSyntax(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https",
      url.user == nil,
      url.password == nil,
      let rawHost = url.host?.lowercased(),
      let host = normalizedHost(rawHost),
      !host.isEmpty
    else { return false }
    guard host != "localhost", !host.hasSuffix(".localhost") else { return false }
    return resolvedAddressSafety(for: host, flags: AI_NUMERICHOST) != false
  }

  package static func resolvesOnlyToPublicAddresses(_ host: String) -> Bool {
    guard let host = normalizedHost(host.lowercased()), !host.isEmpty else { return false }
    return resolvedAddressSafety(for: host, flags: AI_ADDRCONFIG) == true
  }

  private static func normalizedHost(_ host: String) -> String? {
    let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    return normalized.isEmpty ? nil : normalized
  }

  private static func resolvedAddressSafety(for host: String, flags: Int32) -> Bool? {
    var hints = addrinfo()
    hints.ai_flags = flags
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = SOCK_STREAM
    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, nil, &hints, &result) == 0, let result else { return nil }
    defer { freeaddrinfo(result) }

    var foundAddress = false
    var current: UnsafeMutablePointer<addrinfo>? = result
    while let entry = current {
      defer { current = entry.pointee.ai_next }
      guard let address = entry.pointee.ai_addr else { continue }
      switch entry.pointee.ai_family {
      case AF_INET:
        foundAddress = true
        let ipv4 = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
          UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
        }
        if !isPublicIPv4(ipv4) { return false }
      case AF_INET6:
        foundAddress = true
        let bytes = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
          withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) }
        }
        if !isPublicIPv6(bytes) { return false }
      default:
        continue
      }
    }
    return foundAddress ? true : nil
  }

  private static func isPublicIPv4(_ address: UInt32) -> Bool {
    let first = Int((address >> 24) & 0xff)
    let second = Int((address >> 16) & 0xff)
    let third = Int((address >> 8) & 0xff)
    switch (first, second, third) {
    case (0, _, _), (10, _, _), (127, _, _), (169, 254, _), (192, 168, _):
      return false
    case (100, 64...127, _), (172, 16...31, _), (198, 18...19, _):
      return false
    case (192, 0, _), (198, 51, 100), (203, 0, 113):
      return false
    case (224...255, _, _):
      return false
    default:
      return true
    }
  }

  private static func isPublicIPv6(_ bytes: [UInt8]) -> Bool {
    guard bytes.count == 16 else { return false }
    if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
      let ipv4 = bytes[12...15].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
      return isPublicIPv4(ipv4)
    }
    guard (0x20...0x3f).contains(bytes[0]) else { return false }
    if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x0d, bytes[3] == 0xb8 {
      return false
    }
    return true
  }
}

package actor URLSessionArtworkTransport: ArtworkTransport {
  private let redirectDelegate: ArtworkRedirectDelegate
  private let session: URLSession

  package init(cacheDirectoryURL: URL) {
    let redirectDelegate = ArtworkRedirectDelegate()
    self.redirectDelegate = redirectDelegate
    session = URLSession(
      configuration: Self.makeConfiguration(cacheDirectoryURL: cacheDirectoryURL),
      delegate: redirectDelegate,
      delegateQueue: nil
    )
  }

  package nonisolated static func makeConfiguration(
    cacheDirectoryURL: URL
  ) -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = URLCache(
      memoryCapacity: 32 * 1_024 * 1_024,
      diskCapacity: 512 * 1_024 * 1_024,
      directory: cacheDirectoryURL
    )
    configuration.requestCachePolicy = .useProtocolCachePolicy
    configuration.httpCookieAcceptPolicy = .never
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.httpMaximumConnectionsPerHost = 4
    return configuration
  }

  package func data(for url: URL) async throws -> ArtworkResponse {
    do {
      try await validatePublicLocation(url)
      let (bytes, response) = try await session.bytes(from: url)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw ArtworkFailure.transportUnavailable
      }
      guard (200..<300).contains(httpResponse.statusCode) else {
        throw ArtworkFailure.serviceRejected(code: httpResponse.statusCode)
      }
      try await validatePublicLocation(httpResponse.url ?? url)
      guard httpResponse.expectedContentLength <= maximumArtworkDownloadBytes else {
        throw ArtworkFailure.oversizedDownload
      }
      var data = Data()
      if httpResponse.expectedContentLength > 0 {
        data.reserveCapacity(Int(httpResponse.expectedContentLength))
      }
      for try await byte in bytes {
        guard data.count < maximumArtworkDownloadBytes else {
          throw ArtworkFailure.oversizedDownload
        }
        data.append(byte)
      }
      return ArtworkResponse(
        data: data,
        mimeType: httpResponse.mimeType,
        finalURL: httpResponse.url ?? url
      )
    } catch let failure as ArtworkFailure {
      throw failure
    } catch is CancellationError {
      throw ArtworkFailure.cancelled
    } catch let error as URLError where error.code == .cancelled {
      throw ArtworkFailure.cancelled
    } catch {
      throw ArtworkFailure.transportUnavailable
    }
  }

  package func cancelAll() async {
    for task in await session.allTasks {
      task.cancel()
    }
  }

  private func validatePublicLocation(_ url: URL) async throws {
    guard ArtworkLocationPolicy.hasAllowedSyntax(url), let host = url.host else {
      throw ArtworkFailure.insecureLocation
    }
    let isPublic = await Task.detached(priority: .userInitiated) {
      ArtworkLocationPolicy.resolvesOnlyToPublicAddresses(host)
    }.value
    guard isPublic else { throw ArtworkFailure.insecureLocation }
  }
}

package final class ArtworkRedirectDelegate: NSObject, URLSessionTaskDelegate,
  @unchecked Sendable
{
  private static let maximumRedirectCount = 5

  private let lock = NSLock()
  private var redirectCounts: [Int: Int] = [:]

  package override init() {
    super.init()
  }

  package func shouldFollowRedirect(taskIdentifier: Int, url: URL) -> Bool {
    let redirectCount = lock.withLock {
      let next = redirectCounts[taskIdentifier, default: 0] + 1
      redirectCounts[taskIdentifier] = next
      return next
    }
    guard redirectCount <= Self.maximumRedirectCount,
      ArtworkLocationPolicy.hasAllowedSyntax(url),
      let host = url.host,
      ArtworkLocationPolicy.resolvesOnlyToPublicAddresses(host)
    else { return false }
    return true
  }

  package func completed(taskIdentifier: Int) {
    lock.withLock { redirectCounts[taskIdentifier] = nil }
  }

  package func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    guard let url = request.url,
      shouldFollowRedirect(taskIdentifier: task.taskIdentifier, url: url)
    else {
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }

  package func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    completed(taskIdentifier: task.taskIdentifier)
  }
}
