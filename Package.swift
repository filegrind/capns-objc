// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "capdef-objc",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "CapDef",
            targets: ["CapDef"]),
    ],
    targets: [
        .target(
            name: "CapDef",
            dependencies: [],
            path: "Sources/CapDef",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "CapDefTests",
            dependencies: ["CapDef"]),
    ]
)