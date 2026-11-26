// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PLAData",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PLAData",
            targets: ["PLAData"]
        )
    ],
    dependencies: [
        .package(path: "../PLACore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3")
    ],
    targets: [
        .target(
            name: "PLAData",
            dependencies: [
                .product(name: "PLACore", package: "PLACore"),
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/PLAData"
        ),
        .testTarget(
            name: "PLADataTests",
            dependencies: [
                "PLAData",
                .product(name: "PLACore", package: "PLACore")
            ],
            path: "Tests/PLADataTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
