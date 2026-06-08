// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Avelo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Avelo", targets: ["Avelo"])
    ],
    targets: [
        .executableTarget(
            name: "Avelo",
            path: "Avelo",
            exclude: [
                "Resources/SQL/schema_v1.sql",
                "Resources/Seed/DefaultChartOfAccounts.json"
            ],
            resources: [
                .process("Resources/Seed")
            ]
        ),
        .testTarget(
            name: "AveloTests",
            dependencies: ["Avelo"],
            path: "Tests/AveloTests"
        )
    ]
)
