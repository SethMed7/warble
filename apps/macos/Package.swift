// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "voz",
    platforms: [.macOS(.v13)],
    targets: [
        // Two capabilities, each its own module (so their internal types never collide),
        // plus a thin executable that hosts both behind one menu-bar item.
        .target(name: "Speak", path: "Sources/Speak"),
        .target(name: "Dictate", path: "Sources/Dictate"),
        .executableTarget(
            name: "voz",
            dependencies: ["Speak", "Dictate"],
            path: "Sources/voz"
        ),
    ]
)
