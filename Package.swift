// swift-tools-version: 6.0
// version: 0.90.34523
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
    dependencies: [
        .package(path: "../tagged-urn-objc"),
    ],
    targets: [
        .target(
            name: "CapNs",
            dependencies: [
                .product(name: "TaggedUrn", package: "tagged-urn-objc"),
            ],
            path: "Sources/CapNs",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "CapNsTests",
            dependencies: ["CapNs"]),
    ]
)