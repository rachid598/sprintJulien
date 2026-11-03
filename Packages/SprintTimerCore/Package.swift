// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SprintTimerCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "SprintTimerCore", targets: ["SprintTimerCore"])],
    targets: [
        .target(name: "SprintTimerCore"),
        .testTarget(name: "SprintTimerCoreTests", dependencies: ["SprintTimerCore"])
    ]
)
