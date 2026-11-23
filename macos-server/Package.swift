// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DisplayMacServer",
    platforms: [
        .macOS("12.3") // ScreenCaptureKit was introduced in macOS 12.3 Monterey and supported on Ventura (13), Sonoma (14), Sequoia (15), Tahoe (26), Golden Gate (27+)
    ],
    products: [
        .executable(
            name: "DisplayMacServer",
            targets: ["DisplayMacServer"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DisplayMacProtocol",
            dependencies: [],
            path: "Sources/DisplayMacProtocol"
        ),
        .executableTarget(
            name: "DisplayMacServer",
            dependencies: ["DisplayMacProtocol"],
            path: "Sources/DisplayMacServer",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Network"),
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "DisplayMacProtocolTests",
            dependencies: ["DisplayMacProtocol"],
            path: "Tests/DisplayMacProtocolTests"
        )
    ]
)
