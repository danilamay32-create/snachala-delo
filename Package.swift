// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "SnachalaDelo",
    platforms: [.macOS(.v12)],
    targets: [
        .target(name: "Shared"),
        .executableTarget(name: "SnachalaDeloDaemon", dependencies: ["Shared"]),
        .executableTarget(name: "SnachalaDelo", dependencies: ["Shared"]),
    ]
)
