import CoreGraphics
import Foundation
import ImageIO
import MiraioApplication

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
  }

  private struct InFlightDecode: Sendable {
    let id: UUID
    let task: Task<ArtworkImage, any Error>
  }

  private struct DecodedEntry: @unchecked Sendable {
    let image: ArtworkImage
    let cost: Int
    var access: UInt64
  }

  private static let maximumDownloadBytes = 20 * 1_024 * 1_024
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
    guard Self.isAllowed(request.url) else { throw ArtworkFailure.insecureLocation }
    access &+= 1
    if var entry = decoded[request] {
      entry.access = access
      decoded[request] = entry
      return entry.image
    }
    if let inFlight = decodes[request] {
      let image = try await inFlight.task.value
      try Task.checkCancellation()
      return image
    }

    let id = UUID()
    let task = Task { [self] in
      let response = try await download(request.url)
      return try await decode(response: response, for: request)
    }
    decodes[request] = InFlightDecode(id: id, task: task)

    do {
      let image = try await task.value
      if decodes[request]?.id == id { decodes[request] = nil }
      try Task.checkCancellation()
      insertDecoded(image, for: request)
      return image
    } catch is CancellationError {
      if decodes[request]?.id == id { decodes[request] = nil }
      throw ArtworkFailure.cancelled
    } catch let failure as ArtworkFailure {
      if decodes[request]?.id == id { decodes[request] = nil }
      throw failure
    } catch {
      if decodes[request]?.id == id { decodes[request] = nil }
      throw ArtworkFailure.transportUnavailable
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
    if let inFlight = downloads[url] {
      let response = try await inFlight.task.value
      try Task.checkCancellation()
      return response
    }

    let id = UUID()
    let transport = self.transport
    let permits = downloadPermits
    let task = Task {
      try await permits.withPermit {
        try await transport.data(for: url)
      }
    }
    downloads[url] = InFlightDownload(id: id, task: task)

    do {
      let response = try await task.value
      if downloads[url]?.id == id { downloads[url] = nil }
      guard Self.isAllowed(response.finalURL) else { throw ArtworkFailure.insecureLocation }
      guard response.data.count <= Self.maximumDownloadBytes else {
        throw ArtworkFailure.oversizedDownload
      }
      guard response.mimeType?.lowercased().hasPrefix("image/") == true else {
        throw ArtworkFailure.unsupportedContent
      }
      return response
    } catch {
      if downloads[url]?.id == id { downloads[url] = nil }
      throw error
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

  private nonisolated static func isAllowed(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https",
      url.user == nil,
      url.password == nil,
      let host = url.host?.lowercased(),
      !host.isEmpty
    else { return false }
    return !isPrivateAddress(host)
  }

  private nonisolated static func isPrivateAddress(_ host: String) -> Bool {
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
  private let session: URLSession

  package init(cacheDirectoryURL: URL) {
    session = URLSession(configuration: Self.makeConfiguration(cacheDirectoryURL: cacheDirectoryURL))
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
      let (data, response) = try await session.data(from: url)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw ArtworkFailure.transportUnavailable
      }
      guard (200..<300).contains(httpResponse.statusCode) else {
        throw ArtworkFailure.serviceRejected(code: httpResponse.statusCode)
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
