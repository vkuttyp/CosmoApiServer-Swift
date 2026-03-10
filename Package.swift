// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "CosmoApiServer",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "CosmoApiServer", targets: ["CosmoApiServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vkuttyp/CosmoSQLClient-Swift.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.32.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", "5.0.0"..<"5.3.0"),
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0"),
    ],
    targets: [
        Target.macro(
            name: "CosmoMacrosImpl",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        .target(
            name: "CosmoApiServer",
            dependencies: [
                "CosmoMacrosImpl",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOTLS", package: "swift-nio"),
                .product(name: "NIOHTTP2", package: "swift-nio-http2"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOHTTPCompression", package: "swift-nio-extras"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "CosmoSQLCore", package: "CosmoSQLClient-Swift"),
                .product(name: "CosmoMSSQL", package: "CosmoSQLClient-Swift"),
            ]
        ),
        .executableTarget(
            name: "SwiftSqlSample",
            dependencies: [
                "CosmoApiServer",
                .product(name: "CosmoMSSQL", package: "CosmoSQLClient-Swift")
            ],
            path: "Samples/SwiftSqlSample",
            resources: [
                .process("appsettings.json"),
                .copy("wwwroot")
            ]
        ),
        .executableTarget(
            name: "CosmoApiServerBench",
            dependencies: ["CosmoApiServer"]
        ),
        .testTarget(
            name: "CosmoApiServerTests",
            dependencies: ["CosmoApiServer"]
        ),
    ]
)
