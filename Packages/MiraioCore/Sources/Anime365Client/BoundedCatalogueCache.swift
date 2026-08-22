import CryptoKit
import Foundation
import MiraioApplication
import MiraioDomain

public actor BoundedCatalogueCache: CatalogueCache {
  private struct MemoryEntry {
    let snapshot: CatalogueSnapshot
    let byteCost: Int
    var accessSequence: UInt64
  }

  private struct DetailsMemoryEntry {
    let snapshot: CatalogueDetailsSnapshot
    let byteCost: Int
    var accessSequence: UInt64
  }

  private struct DiskEnvelope: Codable {
    let version: Int
    let request: CataloguePageRequest
    let snapshot: CatalogueSnapshot
  }

  private struct DetailsDiskEnvelope: Codable {
    let version: Int
    let id: SeriesID
    let snapshot: CatalogueDetailsSnapshot
  }

  private static let formatVersion = 1

  private let directoryURL: URL
  private let memoryCapacity: Int
  private let diskCapacity: Int
  private var memory: [CataloguePageRequest: MemoryEntry] = [:]
  private var detailsMemory: [SeriesID: DetailsMemoryEntry] = [:]
  private var memoryCost = 0
  private var accessSequence: UInt64 = 0

  public init(directoryURL: URL) {
    self.directoryURL = directoryURL
    memoryCapacity = 32 * 1_024 * 1_024
    diskCapacity = 128 * 1_024 * 1_024
    try? FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
  }

  package init(directoryURL: URL, memoryCapacity: Int, diskCapacity: Int) {
    self.directoryURL = directoryURL
    self.memoryCapacity = memoryCapacity
    self.diskCapacity = diskCapacity
    try? FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
  }

  public func snapshot(for request: CataloguePageRequest) -> CatalogueSnapshot? {
    accessSequence &+= 1
    if var entry = memory[request] {
      entry.accessSequence = accessSequence
      memory[request] = entry
      return entry.snapshot
    }

    let fileURL = fileURL(for: request)
    guard let data = try? Data(contentsOf: fileURL),
      let envelope = try? JSONDecoder().decode(DiskEnvelope.self, from: data),
      envelope.version == Self.formatVersion,
      envelope.request == request
    else {
      try? FileManager.default.removeItem(at: fileURL)
      return nil
    }

    try? FileManager.default.setAttributes(
      [.modificationDate: Date()],
      ofItemAtPath: fileURL.path
    )
    insertIntoMemory(envelope.snapshot, cost: data.count, for: request)
    return envelope.snapshot
  }

  public func store(_ snapshot: CatalogueSnapshot, for request: CataloguePageRequest) {
    let envelope = DiskEnvelope(
      version: Self.formatVersion,
      request: request,
      snapshot: snapshot
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(envelope) else { return }

    insertIntoMemory(snapshot, cost: data.count, for: request)
    guard data.count <= diskCapacity else { return }
    try? FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    try? data.write(to: fileURL(for: request), options: .atomic)
    evictDiskIfNeeded()
  }

  public func details(for id: SeriesID) -> CatalogueDetailsSnapshot? {
    accessSequence &+= 1
    if var entry = detailsMemory[id] {
      entry.accessSequence = accessSequence
      detailsMemory[id] = entry
      return entry.snapshot
    }

    let fileURL = detailsFileURL(for: id)
    guard let data = try? Data(contentsOf: fileURL),
      let envelope = try? JSONDecoder().decode(DetailsDiskEnvelope.self, from: data),
      envelope.version == Self.formatVersion,
      envelope.id == id
    else {
      try? FileManager.default.removeItem(at: fileURL)
      return nil
    }
    try? FileManager.default.setAttributes(
      [.modificationDate: Date()],
      ofItemAtPath: fileURL.path
    )
    insertDetailsIntoMemory(envelope.snapshot, cost: data.count, for: id)
    return envelope.snapshot
  }

  public func store(_ snapshot: CatalogueDetailsSnapshot, for id: SeriesID) {
    let envelope = DetailsDiskEnvelope(version: Self.formatVersion, id: id, snapshot: snapshot)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(envelope) else { return }

    insertDetailsIntoMemory(snapshot, cost: data.count, for: id)
    guard data.count <= diskCapacity else { return }
    try? FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    try? data.write(to: detailsFileURL(for: id), options: .atomic)
    evictDiskIfNeeded()
  }

  public func clear() {
    memory.removeAll(keepingCapacity: false)
    detailsMemory.removeAll(keepingCapacity: false)
    memoryCost = 0
    try? FileManager.default.removeItem(at: directoryURL)
    try? FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
  }

  public func releaseMemory() {
    memory.removeAll(keepingCapacity: false)
    detailsMemory.removeAll(keepingCapacity: false)
    memoryCost = 0
  }

  private func insertIntoMemory(
    _ snapshot: CatalogueSnapshot,
    cost: Int,
    for request: CataloguePageRequest
  ) {
    guard cost <= memoryCapacity else { return }
    accessSequence &+= 1
    if let existing = memory[request] {
      memoryCost -= existing.byteCost
    }
    memory[request] = MemoryEntry(
      snapshot: snapshot,
      byteCost: cost,
      accessSequence: accessSequence
    )
    memoryCost += cost
    evictMemoryIfNeeded()
  }

  private func insertDetailsIntoMemory(
    _ snapshot: CatalogueDetailsSnapshot,
    cost: Int,
    for id: SeriesID
  ) {
    guard cost <= memoryCapacity else { return }
    accessSequence &+= 1
    if let existing = detailsMemory[id] { memoryCost -= existing.byteCost }
    detailsMemory[id] = DetailsMemoryEntry(
      snapshot: snapshot,
      byteCost: cost,
      accessSequence: accessSequence
    )
    memoryCost += cost
    evictMemoryIfNeeded()
  }

  private func evictMemoryIfNeeded() {
    while memoryCost > memoryCapacity, !memory.isEmpty || !detailsMemory.isEmpty {
      let oldestPage = memory.min(by: {
        $0.value.accessSequence < $1.value.accessSequence
      })
      let oldestDetails = detailsMemory.min(by: {
        $0.value.accessSequence < $1.value.accessSequence
      })
      if let oldestPage,
        oldestDetails == nil
          || oldestPage.value.accessSequence <= oldestDetails!.value.accessSequence
      {
        memoryCost -= oldestPage.value.byteCost
        memory[oldestPage.key] = nil
      } else if let oldestDetails {
        memoryCost -= oldestDetails.value.byteCost
        detailsMemory[oldestDetails.key] = nil
      }
    }
  }

  private func fileURL(for request: CataloguePageRequest) -> URL {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = (try? encoder.encode(request)) ?? Data()
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return directoryURL.appending(path: digest).appendingPathExtension("catalogue-cache")
  }

  private func detailsFileURL(for id: SeriesID) -> URL {
    directoryURL
      .appending(path: "series-\(id.rawValue)")
      .appendingPathExtension("catalogue-cache")
  }

  private func evictDiskIfNeeded() {
    let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: Array(keys),
      options: [.skipsHiddenFiles]
    ) else { return }

    let entries = files.compactMap { url -> (url: URL, size: Int, date: Date)? in
      guard let values = try? url.resourceValues(forKeys: keys),
        values.isRegularFile == true,
        let size = values.fileSize
      else { return nil }
      return (url, size, values.contentModificationDate ?? .distantPast)
    }
    var total = entries.reduce(0) { $0 + $1.size }
    for entry in entries.sorted(by: { $0.date < $1.date }) where total > diskCapacity {
      try? FileManager.default.removeItem(at: entry.url)
      total -= entry.size
    }
  }
}
