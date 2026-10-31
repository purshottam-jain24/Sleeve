// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sleeve",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Sleeve", targets: ["Sleeve"])
    ],
    targets: [
        .target(name: "SleeveCore"),
        .target(name: "SleeveAudio"),
        .target(name: "SleeveGlow", dependencies: ["SleeveCore", "SleeveAudio"]),
        // Live video wallpaper and lock-screen artwork (merged from LiveWallpaper).
        .target(name: "SleeveWallpaper"),
        .executableTarget(
            name: "Sleeve",
            dependencies: ["SleeveCore", "SleeveAudio", "SleeveGlow", "SleeveWallpaper"]
        ),
        .testTarget(name: "SleeveCoreTests", dependencies: ["SleeveCore"]),
        .testTarget(name: "SleeveAudioTests", dependencies: ["SleeveAudio"]),
        .testTarget(name: "SleeveGlowTests", dependencies: ["SleeveGlow"]),
        .testTarget(name: "SleeveWallpaperTests", dependencies: ["SleeveWallpaper"]),
    ]
)
