// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyOops",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KeyOopsCore"),
        .executableTarget(name: "VerifyCore", dependencies: ["KeyOopsCore"], path: "Tests/VerifyCore")
    ]
)
