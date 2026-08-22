// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "MiraioCore",
  platforms: [
    .macOS(.v26),
    .iOS(.v26),
  ],
  products: [
    .library(name: "MiraioDomain", targets: ["MiraioDomain"]),
    .library(name: "MiraioApplication", targets: ["MiraioApplication"]),
    .library(name: "Anime365Client", targets: ["Anime365Client"]),
    .library(name: "MiraioCredentials", targets: ["MiraioCredentials"]),
    .library(name: "MiraioWatchHistory", targets: ["MiraioWatchHistory"]),
    .library(name: "MiraioPlayback", targets: ["MiraioPlayback"]),
    .library(name: "MiraioASSRenderer", targets: ["MiraioASSRenderer"]),
    .library(name: "MiraioArtwork", targets: ["MiraioArtwork"]),
  ],
  targets: [
    .target(name: "MiraioDomain"),
    .target(name: "MiraioApplication", dependencies: ["MiraioDomain"]),
    .target(name: "Anime365Client", dependencies: ["MiraioApplication", "MiraioDomain"]),
    .target(name: "MiraioCredentials", dependencies: ["MiraioApplication", "MiraioDomain"]),
    .target(name: "MiraioWatchHistory", dependencies: ["MiraioApplication", "MiraioDomain"]),
    .target(name: "MiraioPlayback", dependencies: ["MiraioApplication", "MiraioDomain"]),
    .target(name: "MiraioASSRenderer", dependencies: ["MiraioPlayback", "MiraioDomain"]),
    .target(name: "MiraioArtwork", dependencies: ["MiraioApplication", "MiraioDomain"]),
    .testTarget(name: "MiraioDomainTests", dependencies: ["MiraioDomain"]),
    .testTarget(name: "MiraioApplicationTests", dependencies: ["MiraioApplication"]),
    .testTarget(
      name: "Anime365ClientTests",
      dependencies: ["Anime365Client", "MiraioApplication", "MiraioDomain"]
    ),
    .testTarget(
      name: "MiraioArtworkTests",
      dependencies: ["MiraioArtwork", "MiraioApplication"]
    ),
  ]
)
