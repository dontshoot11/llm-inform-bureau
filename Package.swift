// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LLMInformBureau",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SessionHealthCore", targets: ["SessionHealthCore"]),
        .library(name: "AgentFiles", targets: ["AgentFiles"]),
        .library(name: "Phrasing", targets: ["Phrasing"]),
        .executable(name: "LLMInformBureau", targets: ["LLMInformBureau"])
    ],
    targets: [
        .target(
            name: "SessionHealthCore",
            // The .md files next to the code are documentation for people, not resources.
            exclude: ["SessionHealthCore.md", "Thresholds.md"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "AgentFiles",
            dependencies: ["SessionHealthCore"],
            exclude: ["AgentFiles.md"]
        ),
        // The English the widget speaks, kept out of the app target so that the wording of a
        // notification is covered by the test suite — an executable target cannot be imported.
        .target(
            name: "Phrasing",
            dependencies: ["SessionHealthCore"],
            exclude: ["Phrasing.md"]
        ),
        // The menu bar app. Built into a .app bundle by Scripts/build-app.sh — SwiftPM
        // produces the executable, and a menu bar app needs a bundle with LSUIElement.
        .executableTarget(
            name: "LLMInformBureau",
            dependencies: ["SessionHealthCore", "AgentFiles", "Phrasing"],
            exclude: ["LLMInformBureau.md"]
        ),
        // Not a SwiftPM test target on purpose: XCTest and swift-testing ship inside
        // Xcode, and this package is built with the Command Line Tools alone.
        // See Tests/SessionHealthTests/SessionHealthTests.md.
        .executableTarget(
            name: "SessionHealthTests",
            dependencies: ["SessionHealthCore", "AgentFiles", "Phrasing"],
            path: "Tests/SessionHealthTests",
            exclude: ["SessionHealthTests.md"]
        )
    ]
)
