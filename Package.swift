// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mally",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Mally", targets: ["Mally"])
    ],
    targets: [
        .executableTarget(
            name: "Mally",
            path: "Mally",
            exclude: [
                "Resources/SQL/schema_v1.sql",
                "Resources/Seed/DefaultChartOfAccounts.json"
            ],
            resources: [
                .process("Resources/Seed")
            ]
        )
    ]
)
