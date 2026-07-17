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
        .target(
            name: "CSQLCipher",
            path: "Vendor/SQLCipher",
            publicHeadersPath: ".",
            cSettings: [
                .define("SQLITE_HAS_CODEC"),
                .define("SQLCIPHER_CRYPTO_CC"),
                .define("SQLITE_EXTRA_INIT", to: "sqlcipher_extra_init"),
                .define("SQLITE_EXTRA_SHUTDOWN", to: "sqlcipher_extra_shutdown"),
                .define("SQLITE_THREADSAFE", to: "1"),
                .define("SQLITE_TEMP_STORE", to: "2"),
                .define("NDEBUG")
            ]
        ),
        .executableTarget(
            name: "Avelo",
<<<<<<< HEAD
            dependencies: ["CSQLCipher"],
=======
>>>>>>> origin/main
            path: "Avelo",
            exclude: [
                "Avelo.entitlements",
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
