// swift-tools-version: 6.0
// version: 0.176.68564
import PackageDescription

let package = Package(
    name: "capns-objc",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "CapNs",
            targets: ["CapNs"]),
        .library(
            name: "Bifaci",
            targets: ["Bifaci"]),
    ],
    dependencies: [
        .package(path: "../tagged-urn-objc"),
        .package(path: "../ops-objc"),
        .package(url: "https://github.com/unrelentingtech/SwiftCBOR.git", from: "0.4.7"),
        .package(url: "https://github.com/Bouke/Glob.git", from: "1.0.0"),
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
            name: "Bifaci",
            dependencies: [
                "CapNs",
                .product(name: "Ops", package: "ops-objc"),
                .product(name: "SwiftCBOR", package: "SwiftCBOR"),
                .product(name: "Glob", package: "Glob"),
            ],
            path: "Sources/Bifaci"
        ),
        .testTarget(
            name: "CapNsTests",
            dependencies: ["CapNs"]),
        .testTarget(
            name: "BifaciTests",
            dependencies: [
                "Bifaci",
                .product(name: "SwiftCBOR", package: "SwiftCBOR"),
            ]),
    ]
)
