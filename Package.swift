// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacAsistan",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacAsistan", targets: ["MacAsistan"])
    ],
    targets: [
        .executableTarget(
            name: "MacAsistan",
            path: "Sources/MacAsistan"
        )
    ]
)
