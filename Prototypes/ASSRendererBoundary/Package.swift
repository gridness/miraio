// swift-tools-version: 6.2

import Foundation
import PackageDescription

let libassPrefix = ProcessInfo.processInfo.environment["LIBASS_PREFIX"] ?? "/opt/homebrew/opt/libass"

let package = Package(
    name: "ASSRendererBoundaryPrototype",
    platforms: [.macOS(.v26)],
    products: [
        .executable(
            name: "ASSRendererBoundaryPrototype",
            targets: ["ASSRendererBoundaryPrototype"]
        )
    ],
    targets: [
        .target(
            name: "ASSBridge",
            path: "Sources/ASSBridge",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I", "\(libassPrefix)/include"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L", "\(libassPrefix)/lib"]),
                .linkedLibrary("ass")
            ]
        ),
        .executableTarget(
            name: "ASSRendererBoundaryPrototype",
            dependencies: ["ASSBridge"],
            path: "Sources/ASSRendererBoundaryPrototype",
            resources: [.copy("Fixtures")]
        )
    ]
)
