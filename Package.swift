// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FirstStep",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "FirstStep", targets: ["FocusApp"])],
    targets: [
        .target(name: "FocusCore"),
        .target(name: "FocusAI"),
        .executableTarget(name: "FocusApp", dependencies: ["FocusCore", "FocusAI"])
    ]
)
