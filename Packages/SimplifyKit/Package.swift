// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SimplifyKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "SimplifyKit", targets: ["SimplifyKit"]),
    ],
    targets: [
        .target(name: "SimplifyKit"),
        .testTarget(name: "SimplifyKitTests", dependencies: ["SimplifyKit"]),
    ]
)
