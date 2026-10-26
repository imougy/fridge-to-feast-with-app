// swift-tools-version: 5.9
import PackageDescription

// FridgeToFeastCore: the model pipeline for Fridge-to-Feast.
// Foundation-only on purpose: it builds anywhere Swift builds, and the
// SwiftUI app shell (see ../App) depends on it, never the reverse.
let package = Package(
    name: "FridgeToFeast",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "FridgeToFeastCore", targets: ["FridgeToFeastCore"])
    ],
    targets: [
        .target(name: "FridgeToFeastCore"),
        .testTarget(name: "FridgeToFeastCoreTests", dependencies: ["FridgeToFeastCore"])
    ]
)
