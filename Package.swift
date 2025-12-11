// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftEvolution",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "main",
            targets: ["Main"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Main",
            path: ".",
            exclude: [
                ".build",
                "BUILD.md",
                "CHANGELOG.md",
                "Info.plist",
                "LICENSE.md",
                "Makefile",
                "Package.swift",
                "README.md",
                "icon.png",
                "screenshots",
            ],
            sources: ["main.swift"]
        )
    ]
)
