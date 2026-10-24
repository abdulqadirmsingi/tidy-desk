// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TidyDesk",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "TidyDesk", targets: ["TidyDesk"]),
        .library(name: "TidyDeskCore", targets: ["TidyDeskCore"]),
    ],
    targets: [
        .target(name: "TidyDeskCore"),
        .executableTarget(
            name: "TidyDesk",
            dependencies: ["TidyDeskCore"]
        ),
        .testTarget(
            name: "TidyDeskCoreTests",
            dependencies: ["TidyDeskCore"]
        ),
        .testTarget(
            name: "TidyDeskTests",
            dependencies: ["TidyDesk", "TidyDeskCore"]
        ),
    ]
)
