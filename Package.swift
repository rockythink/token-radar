// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "TokenRadar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TokenRadar", targets: ["TokenRadar"]),
        .executable(name: "TokenRadarCoreChecks", targets: ["TokenRadarCoreChecks"]),
        .library(name: "TokenRadarCore", targets: ["TokenRadarCore"])
    ],
    targets: [
        .target(
            name: "TokenRadarCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "TokenRadar",
            dependencies: ["TokenRadarCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "TokenRadarCoreChecks",
            dependencies: ["TokenRadarCore"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
