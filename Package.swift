// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Needle",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NeedleCore", targets: ["NeedleCore"]),
        .executable(name: "NeedleApp", targets: ["NeedleApp"])
    ],
    targets: [
        .target(
            name: "NeedleCore",
            path: "Sources/NeedleCore"
        ),
        .executableTarget(
            name: "NeedleApp",
            dependencies: ["NeedleCore"],
            path: "Sources/NeedleApp"
        ),
        .executableTarget(
            name: "NeedleCoreTests",
            dependencies: ["NeedleCore"],
            path: "Tests/NeedleCoreTests"
        )
    ]
)
