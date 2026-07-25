// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Signal",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SignalCore", targets: ["SignalCore"]),
        .executable(name: "Signal", targets: ["SignalApp"])
    ],
    targets: [
        .target(name: "SignalCore"),
        .executableTarget(
            name: "SignalApp",
            dependencies: ["SignalCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Vision"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .testTarget(name: "SignalCoreTests", dependencies: ["SignalCore"])
    ]
)
