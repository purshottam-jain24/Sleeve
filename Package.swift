// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Afterglow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Afterglow", targets: ["Afterglow"])
    ],
    targets: [
        .target(name: "AfterglowCore"),
        .target(name: "AfterglowAudio"),
        .target(name: "AfterglowGlow", dependencies: ["AfterglowCore", "AfterglowAudio"]),
        .executableTarget(
            name: "Afterglow",
            dependencies: ["AfterglowCore", "AfterglowAudio", "AfterglowGlow"]
        ),
        .testTarget(name: "AfterglowCoreTests", dependencies: ["AfterglowCore"]),
        .testTarget(name: "AfterglowAudioTests", dependencies: ["AfterglowAudio"]),
        .testTarget(name: "AfterglowGlowTests", dependencies: ["AfterglowGlow"]),
    ]
)
