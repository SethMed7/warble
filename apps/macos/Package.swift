// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "warble",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Sparkle: in-app "Check for Updates…" + a quiet scheduled check, with secure (EdDSA-signed)
        // download/replace/relaunch. The ONLY external dependency — used only by the `warble` app target;
        // the portable `core/` and the capability modules stay dependency-free.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Two capabilities, each its own module (so their internal types never collide),
        // a tiny Shared module for things both need (e.g. the single Escape-hotkey owner),
        // plus a thin executable that hosts both behind one menu-bar item.
        .target(name: "Shared", path: "Sources/Shared", resources: [.copy("Resources")]),
        .target(name: "Speak", dependencies: ["Shared"], path: "Sources/Speak"),
        .target(name: "Dictate", dependencies: ["Shared"], path: "Sources/Dictate"),
        .executableTarget(
            name: "warble",
            dependencies: ["Speak", "Dictate", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/warble"
        ),
    ]
)
