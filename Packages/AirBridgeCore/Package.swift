// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AirBridgeCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AirBridgeCore", targets: ["AirBridgeCore"]),
    ],
    targets: [
        .target(name: "AirBridgeCore"),
        .testTarget(name: "AirBridgeCoreTests", dependencies: ["AirBridgeCore"]),
    ]
)
