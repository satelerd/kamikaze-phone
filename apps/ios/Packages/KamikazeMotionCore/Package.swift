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
        .executable(name: "kamikaze-motion-eval", targets: ["KamikazeMotionEvaluation"]),
    ],
    targets: [
        .target(name: "KamikazeMotionCore"),
        .executableTarget(
            name: "KamikazeMotionEvaluation",
            dependencies: ["KamikazeMotionCore"]
        ),
        .testTarget(name: "KamikazeMotionCoreTests", dependencies: ["KamikazeMotionCore"]),
    ]
)
