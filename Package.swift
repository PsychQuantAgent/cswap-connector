// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "cswap-connector",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "cswap-connector", targets: ["cswap-connector"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.0"),
    ],
    targets: [
        .target(name: "CswapCore"),
        .executableTarget(
            name: "cswap-connector",
            dependencies: [
                "CswapCore",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(
            name: "CswapCoreTests",
            dependencies: ["CswapCore", "cswap-connector"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
