// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "YesEngineer",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "SharedTypes",
            path: "Sources/SharedTypes"
        ),
        .executableTarget(
            name: "YesEngineerDaemon",
            dependencies: ["SharedTypes"],
            path: "Sources/YesEngineerDaemon"
        ),
        .executableTarget(
            name: "YesEngineer",
            dependencies: ["SharedTypes"],
            path: "Sources/YesEngineer"
        ),
        .testTarget(
            name: "YesEngineerTests",
            dependencies: ["YesEngineer"],
            path: "Tests/YesEngineerTests"
        ),
    ]
)
