// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KamikazeMotionApple",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "KamikazeMotionApple", targets: ["KamikazeMotionApple"]),
    ],
    dependencies: [
        .package(path: "../KamikazeMotionCore"),
    ],
    targets: [
        .target(
            name: "KamikazeMotionApple",
            dependencies: ["KamikazeMotionCore"]
        ),
    ]
)
