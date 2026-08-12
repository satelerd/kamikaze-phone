// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KamikazeMotionCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "KamikazeMotionCore", targets: ["KamikazeMotionCore"]),
    ],
    targets: [
        .target(name: "KamikazeMotionCore"),
        .testTarget(name: "KamikazeMotionCoreTests", dependencies: ["KamikazeMotionCore"]),
    ]
)
