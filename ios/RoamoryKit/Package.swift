// swift-tools-version: 6.2
import PackageDescription

// Phone-side modules that run without the app target: Edit (plan, validate, render), Signals, Cloud and Config.
// detector-replay is a Mac tool that runs a recorded walk through Stage 1 detection.
// The app adds this as a local package; the logic builds and tests on macOS too.
let package = Package(
    name: "RoamoryKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "RoamoryKit", targets: ["RoamoryKit"]),
        .executable(name: "detector-replay", targets: ["DetectorReplay"]),
    ],
    targets: [
        .target(
            name: "RoamoryKit",
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "DetectorReplay",
            dependencies: ["RoamoryKit"]
        ),
        .testTarget(
            name: "RoamoryKitTests",
            dependencies: ["RoamoryKit"]
        ),
    ]
)
