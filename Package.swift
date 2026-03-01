// swift-tools-version: 6.0
// version: 0.196.80351
import PackageDescription

let package = Package(
    name: "capdag-objc",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "CapDAG",
            targets: ["CapDAG"]),
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
            name: "CapDAG",
            dependencies: [
                .product(name: "TaggedUrn", package: "tagged-urn-objc"),
            ],
            path: "Sources/CapDAG",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "Bifaci",
            dependencies: [
                "CapDAG",
                .product(name: "Ops", package: "ops-objc"),
                .product(name: "SwiftCBOR", package: "SwiftCBOR"),
                .product(name: "Glob", package: "Glob"),
            ],
            path: "Sources/Bifaci"
        ),
        .testTarget(
            name: "CapDAGTests",
            dependencies: ["CapDAG"]),
        .testTarget(
            name: "BifaciTests",
            dependencies: [
                "Bifaci",
                .product(name: "SwiftCBOR", package: "SwiftCBOR"),
            ]),
    ]
)
