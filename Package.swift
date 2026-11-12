// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KoEnFix",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "KoEnFix",
            path: "Sources"
        )
    ]
)
