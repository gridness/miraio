import CoreGraphics
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
    let cost: Int
    var access: UInt64
  }

  private static let maximumPixels = 40_000_000
  private static let decodedCapacity = 128 * 1_024 * 1_024

  private let transport: any ArtworkTransport
  private let downloadPermits = AsyncPermitPool(limit: 4)
  private let decodePermits = AsyncPermitPool(limit: 2)
  private var downloads: [URL: InFlightDownload] = [:]
  private var decodes: [ArtworkRequest: InFlightDecode] = [:]
  private var decoded: [ArtworkRequest: DecodedEntry] = [:]
  private var decodedCost = 0
  private var access: UInt64 = 0

  public init(cacheDirectoryURL: URL) {
    transport = URLSessionArtworkTransport(cacheDirectoryURL: cacheDirectoryURL)
  }

  package init(transport: any ArtworkTransport) {
    self.transport = transport
  }

  public func image(for request: ArtworkRequest) async throws -> ArtworkImage {
    guard ArtworkLocationPolicy.isAllowed(request.url) else {
      throw ArtworkFailure.insecureLocation
    }
    access &+= 1
    if var entry = decoded[request] {
      entry.access = access
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
        guard ArtworkLocationPolicy.isAllowed(response.finalURL) else {
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
    return try await permits.withPermit {
      try await Task.detached(priority: .userInitiated) {
        try Self.decodeOffMain(response.data, request: request)
      }.value
    }
  }

  private nonisolated static func decodeOffMain(
    _ data: Data,
    request: ArtworkRequest
  ) throws -> ArtworkImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0,
      height > 0
    else { throw ArtworkFailure.malformedImage }
    guard width <= maximumPixels / height else { throw ArtworkFailure.oversizedImage }

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(request.pixelWidth, request.pixelHeight),
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { throw ArtworkFailure.malformedImage }
    return ArtworkImage(cgImage: image)
  }

  private func insertDecoded(_ image: ArtworkImage, for request: ArtworkRequest) {
    let bytesPerRow = image.cgImage.bytesPerRow
    guard image.cgImage.height <= Self.decodedCapacity / max(1, bytesPerRow) else { return }
    let cost = bytesPerRow * image.cgImage.height
    access &+= 1
    if let existing = decoded[request] { decodedCost -= existing.cost }
    decoded[request] = DecodedEntry(image: image, cost: cost, access: access)
    decodedCost += cost
    while decodedCost > Self.decodedCapacity,
      let oldest = decoded.min(by: { $0.value.access < $1.value.access })
    {
      decodedCost -= oldest.value.cost
      decoded[oldest.key] = nil
    }
  }

}

private enum ArtworkLocationPolicy {
  static func isAllowed(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https",
      url.user == nil,
      url.password == nil,
      let host = url.host?.lowercased(),
      !host.isEmpty
    else { return false }
    return !isPrivateAddress(host)
  }

  private static func isPrivateAddress(_ host: String) -> Bool {
    if host == "localhost" || host == "::1" { return true }
    if host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe8")
      || host.hasPrefix("fe9") || host.hasPrefix("fea") || host.hasPrefix("feb")
    {
      return true
    }
    let octets = host.split(separator: ".").compactMap { Int($0) }
    guard octets.count == 4 else { return false }
    switch (octets[0], octets[1]) {
    case (0, _), (10, _), (127, _), (169, 254), (192, 168): return true
    case (172, 16...31): return true
    case (224...255, _): return true
    default: return false
    }
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
    configuration.httpMaximumConnectionsPerHost = 4
    return configuration
  }

  package func data(for url: URL) async throws -> ArtworkResponse {
    do {
      let (bytes, response) = try await session.bytes(from: url)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw ArtworkFailure.transportUnavailable
      }
      guard (200..<300).contains(httpResponse.statusCode) else {
        throw ArtworkFailure.serviceRejected(code: httpResponse.statusCode)
      }
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
}

private final class ArtworkRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private static let maximumRedirectCount = 5

  private let lock = NSLock()
  private var redirectCounts: [Int: Int] = [:]

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    let redirectCount = lock.withLock {
      let next = redirectCounts[task.taskIdentifier, default: 0] + 1
      redirectCounts[task.taskIdentifier] = next
      return next
    }
    guard redirectCount <= Self.maximumRedirectCount,
      let url = request.url,
      ArtworkLocationPolicy.isAllowed(url)
    else {
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    lock.withLock { redirectCounts[task.taskIdentifier] = nil }
  }
}
