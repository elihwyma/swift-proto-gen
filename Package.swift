// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-proto-gen",
    products: [
        .library(name: "SwiftProtoGen", targets: ["SwiftProtoGen"]),
        .plugin(name: "SwiftProtoGenPlugin", targets: ["SwiftProtoGenPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.30.0")
    ],
    targets: [
        .target(
            name: "SwiftProtoGen",
            dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")]
        ),
        .executableTarget(
            name: "swift-proto-gen",
            dependencies: [.product(name: "SwiftProtobufPluginLibrary", package: "swift-protobuf")]
        ),
        .plugin(
            name: "SwiftProtoGenPlugin",
            capability: .buildTool(),
            dependencies: [
                "swift-proto-gen",
                .product(name: "protoc-gen-swift", package: "swift-protobuf"),
            ]
        ),
        .testTarget(
            name: "SwiftProtoGenTests",
            dependencies: ["SwiftProtoGen"],
            plugins: ["SwiftProtoGenPlugin"]
        ),
    ]
)
