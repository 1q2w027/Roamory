// swift-tools-version: 6.2
import PackageDescription

// Phone-side modules that run without the app target: Edit (plan, validate, render), Cloud and Config.
// The app adds this as a local package; the logic builds and tests on macOS too.
let package = Package(
    name: "RoamoryKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "RoamoryKit", targets: ["RoamoryKit"])
    ],
    targets: [
        .target(
            name: "RoamoryKit",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "RoamoryKitTests",
            dependencies: ["RoamoryKit"]
        ),
    ]
)
