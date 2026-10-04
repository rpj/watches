// swift-tools-version: 5.10
import PackageDescription

// iOS-only code shared by the Wrist app and the WristWidget extension:
// Keychain, App Group storage, URLSession transport, notification scheduling,
// and the composition root. Pure logic lives in ../WristCore so it can be
// tested on Linux; nothing in here is expected to build outside Xcode.
let package = Package(
    name: "WristKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "WristKit", targets: ["WristKit"]),
    ],
    dependencies: [
        .package(path: "../WristCore"),
    ],
    targets: [
        .target(
            name: "WristKit",
            dependencies: [
                .product(name: "WristCore", package: "WristCore"),
            ]
        ),
    ]
)
