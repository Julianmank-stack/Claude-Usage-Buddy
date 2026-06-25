// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ClaudeUsageBuddy",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeUsageBuddy",
            path: "Sources/ClaudeUsageBuddy"
        )
    ]
)
