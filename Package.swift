// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Syncorda",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SyncordaCore", targets: ["SyncordaCore"]),
        .executable(name: "SyncordaApp", targets: ["SyncordaApp"]),
        .executable(name: "syncordactl", targets: ["syncordactl"]),
        .executable(name: "syncordachecks", targets: ["syncordachecks"])
    ],
    targets: [
        .target(name: "SyncordaAtomics", publicHeadersPath: "include"),
        .target(name: "SyncordaCore", dependencies: ["SyncordaAtomics"]),
        .executableTarget(name: "SyncordaApp", dependencies: ["SyncordaCore"]),
        .executableTarget(name: "syncordactl", dependencies: ["SyncordaCore"]),
        .executableTarget(name: "syncordachecks", dependencies: ["SyncordaCore"])
    ]
)
