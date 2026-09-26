// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenDeviceHub",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenDeviceHubEngine", targets: ["OpenDeviceHubEngine"]),
        .library(name: "OpenDeviceHubViewer", targets: ["OpenDeviceHubViewer"]),
        .executable(name: "odhub", targets: ["odhub"]),
        .executable(name: "odhub-viewer", targets: ["ODHubViewerApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(name: "OpenDeviceHubPrivate"),
        .target(
            name: "OpenDeviceHubEngine",
            dependencies: ["OpenDeviceHubPrivate"]
        ),
        .target(
            name: "OpenDeviceHubViewer",
            dependencies: [
                "OpenDeviceHubEngine",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "odhub",
            dependencies: [
                "OpenDeviceHubEngine",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "ODHubViewerApp",
            dependencies: [
                "OpenDeviceHubEngine",
                "OpenDeviceHubViewer",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "OpenDeviceHubEngineTests",
            dependencies: ["OpenDeviceHubEngine"]
        ),
        .testTarget(
            name: "OpenDeviceHubViewerTests",
            dependencies: ["OpenDeviceHubViewer"]
        ),
        .testTarget(
            name: "OpenDeviceHubIntegrationTests",
            dependencies: ["OpenDeviceHubEngine", "OpenDeviceHubViewer"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
