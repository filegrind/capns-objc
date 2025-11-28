// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "capns-objc",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "CapNs",
            targets: ["CapNs"]),
    ],
    targets: [
        .target(
            name: "CapNs",
            dependencies: [],
            path: "Sources/CapNs",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "CapNsTests",
            dependencies: ["CapNs"]),
    ]
)