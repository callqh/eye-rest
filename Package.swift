// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "EyeRest",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "EyeRest", targets: ["EyeRestApp"]), .executable(name: "RestEngineChecks", targets: ["RestEngineChecks"])],
    targets: [
        .target(name: "EyeRestCore"),
        .executableTarget(name: "EyeRestApp", dependencies: ["EyeRestCore"], exclude: ["Resources"]),
        .executableTarget(name: "RestEngineChecks", dependencies: ["EyeRestCore"], path: "Tests/EyeRestCoreTests")
    ]
)
