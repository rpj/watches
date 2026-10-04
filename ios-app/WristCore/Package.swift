// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WristCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WristCore", targets: ["WristCore"]),
    ],
    targets: [
        .target(name: "WristCore"),
        .testTarget(name: "WristCoreTests", dependencies: ["WristCore"]),
    ]
)
