// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ProcessTapSpike",
    platforms: [.macOS("14.4")],
    targets: [
        .executableTarget(name: "ProcessTapSpike")
    ]
)
