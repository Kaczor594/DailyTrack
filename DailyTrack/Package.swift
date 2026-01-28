// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DailyTrack",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "DailyTrack",
            path: ".",
            exclude: ["Package.swift"],
            resources: [
                .process("Sources/Localization")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
