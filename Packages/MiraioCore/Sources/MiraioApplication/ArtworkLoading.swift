import CoreGraphics
import Foundation

public struct ArtworkRequest: Hashable, Sendable {
  public let url: URL
  public let pixelWidth: Int
  public let pixelHeight: Int
  public let scale: Double

  public init?(url: URL, pixelWidth: Int, pixelHeight: Int, scale: Double) {
    guard pixelWidth > 0, pixelHeight > 0, scale > 0 else { return nil }
    self.url = url
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.scale = scale
  }
}

public struct ArtworkImage: @unchecked Sendable {
  public let cgImage: CGImage

  public init(cgImage: CGImage) {
    self.cgImage = cgImage
  }
}

public enum ArtworkFailure: Error, Equatable, Sendable {
  case insecureLocation
  case transportUnavailable
  case serviceRejected(code: Int)
  case oversizedDownload
  case oversizedImage
  case unsupportedContent
  case malformedImage
  case cancelled
}

public protocol ArtworkLoading: Sendable {
  func image(for request: ArtworkRequest) async throws -> ArtworkImage
  func cancelNonessentialWork() async
  func releaseDecodedImages() async
}
