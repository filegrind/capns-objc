// swift-tools-version: 6.0
// version: 0.90.34524
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
        .library(
            name: "CapNsCbor",
            targets: ["CapNsCbor"]),
    ],
    dependencies: [
        .package(path: "../tagged-urn-objc"),
        .package(url: "https://github.com/unrelentingtech/SwiftCBOR.git", from: "0.4.7"),
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
        .target(
            name: "CapNsCbor",
            dependencies: [
                "CapNs",
                .product(name: "SwiftCBOR", package: "SwiftCBOR"),
            ],
            path: "Sources/CapNsCbor"
        ),
        .testTarget(
            name: "CapNsTests",
            dependencies: ["CapNs"]),
        .testTarget(
            name: "CapNsCborTests",
            dependencies: [
                "CapNsCbor",
                .product(name: "SwiftCBOR", package: "SwiftCBOR"),
            ]),
    ]
)
