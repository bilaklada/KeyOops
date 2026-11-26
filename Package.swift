// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyOops",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KeyOopsCore"),
        .target(name: "MacLayouts", dependencies: ["KeyOopsCore"]),
        .executableTarget(name: "VerifyLayouts", dependencies: ["MacLayouts"], path: "Tests/VerifyLayouts"),
        .executableTarget(name: "VerifyCore", dependencies: ["KeyOopsCore"], path: "Tests/VerifyCore")
    ]
)
