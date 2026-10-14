// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "apple-reminders-cli",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Library product for RemindersKit
        .library(
            name: "RemindersKit",
            targets: ["RemindersKit"]
        ),
        // Executable product for the CLI
        .executable(
            name: "reminders-cli",
            targets: ["reminders-cli"]
        ),
    ],
    dependencies: [
        // No external dependencies - EventKit is built into macOS
    ],
    targets: [
        // Library target - Core reminder functionality
        .target(
            name: "RemindersKit",
            dependencies: []
        ),
        // Executable target - CLI entry point
        .executableTarget(
            name: "reminders-cli",
            dependencies: ["RemindersKit"]
        ),
        // Test target - Swift Testing, in-memory only (no Reminders access needed).
        // Tests/RemindersKitTests must exist: a test target with no directory makes
        // SPM fall back to Sources/ and overlap the main targets.
        .testTarget(
            name: "RemindersKitTests",
            dependencies: ["RemindersKit"]
        ),
    ]
)

