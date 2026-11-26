// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyOops",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KeyOopsCore", resources: [.process("Data")]),
        .target(name: "MacLayouts", dependencies: ["KeyOopsCore"]),
        .target(name: "SelectionService", dependencies: ["KeyOopsCore", "MacLayouts"]),
        .executableTarget(name: "KeyOops", dependencies: ["SelectionService", "MacLayouts", "KeyOopsCore"]),
        .executableTarget(name: "VerifyLiveEdit", dependencies: ["MacLayouts"], path: "Tests/VerifyLiveEdit"),
        .executableTarget(name: "VerifyService", dependencies: ["SelectionService", "KeyOopsCore"], path: "Tests/VerifyService"),
        .executableTarget(name: "VerifyLayouts", dependencies: ["MacLayouts"], path: "Tests/VerifyLayouts"),
        .executableTarget(name: "VerifyCore", dependencies: ["KeyOopsCore"], path: "Tests/VerifyCore")
    ]
)
