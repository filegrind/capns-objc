// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "capability-sdk-objc",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "CapabilitySDK",
            targets: ["CapabilitySDK"]),
    ],
    targets: [
        .target(
            name: "CapabilitySDK",
            dependencies: [],
            path: "Sources/CapabilitySDK",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "CapabilitySDKTests",
            dependencies: ["CapabilitySDK"]),
    ]
)