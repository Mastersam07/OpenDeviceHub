// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenDeviceHub",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenDeviceHubEngine", targets: ["OpenDeviceHubEngine"]),
        .library(name: "OpenDeviceHubViewer", targets: ["OpenDeviceHubViewer"]),
        .executable(name: "odhub", targets: ["odhub"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "OpenDeviceHubPrivate"),
        .target(
            name: "OpenDeviceHubEngine",
            dependencies: ["OpenDeviceHubPrivate"]
        ),
        .target(
            name: "OpenDeviceHubViewer",
            dependencies: ["OpenDeviceHubEngine"]
        ),
        .executableTarget(
            name: "odhub",
            dependencies: [
                "OpenDeviceHubEngine",
                "OpenDeviceHubViewer",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "OpenDeviceHubEngineTests",
            dependencies: ["OpenDeviceHubEngine"]
        ),
        .testTarget(
            name: "OpenDeviceHubIntegrationTests",
            dependencies: ["OpenDeviceHubEngine"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
