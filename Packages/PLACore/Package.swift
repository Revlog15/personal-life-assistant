// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PLACore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PLACore",
            targets: ["PLACore"]
        )
    ],
    targets: [
        .target(
            name: "PLACore",
            path: "Sources/PLACore"
        ),
        .testTarget(
            name: "PLACoreTests",
            dependencies: ["PLACore"],
            path: "Tests/PLACoreTests"
        )
    ]
)
