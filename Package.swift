// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Needle",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NeedleCore", targets: ["NeedleCore"])
    ],
    targets: [
        .target(
            name: "NeedleCore",
            path: "Sources/NeedleCore"
        ),
        .executableTarget(
            name: "NeedleCoreTests",
            dependencies: ["NeedleCore"],
            path: "Tests/NeedleCoreTests"
        )
    ]
)
