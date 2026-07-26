// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "macness",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "macness", targets: ["macness"]),
        .library(name: "MacnessCore", targets: ["MacnessCore"]),
    ],
    targets: [
        .target(
            name: "MacnessCore",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .executableTarget(
            name: "macness",
            dependencies: ["MacnessCore"]
        ),
        .testTarget(
            name: "MacnessCoreTests",
            dependencies: ["MacnessCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
