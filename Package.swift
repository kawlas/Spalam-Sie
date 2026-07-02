// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Spalam Sie",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sbooth/SFBAudioEngine", from: "0.9.1"),
    ],
    targets: [
        .executableTarget(
            name: "Spalam Sie",
            dependencies: [
                .product(name: "SFBAudioEngine", package: "SFBAudioEngine"),
            ],
            path: "Sources",
            resources: [
                .copy("Spalam Sie/Resources/SpalamSie.icns"),
            ]
        ),
        .testTarget(
            name: "Spalam SieTests",
            dependencies: ["Spalam Sie"],
            path: "Tests/CoreTests"
        ),
        .testTarget(
            name: "DataDiscTests",
            dependencies: ["Spalam Sie"],
            path: "Tests/DataDiscTests"
        ),
        .testTarget(
            name: "CopyDiscTests",
            dependencies: ["Spalam Sie"],
            path: "Tests/CopyDiscTests"
        ),
        .testTarget(
            name: "PlayerTests",
            dependencies: ["Spalam Sie"],
            path: "Tests/PlayerTests"
        ),
        .testTarget(
            name: "VideoDVDTests",
            dependencies: ["Spalam Sie"],
            path: "Tests/VideoDVDTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
