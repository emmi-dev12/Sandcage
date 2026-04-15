// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sandcage",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Sandcage",
            path: "Sources/Sandcage",
            resources: [
                .copy("Profiles")
            ]
        )
    ]
)
