// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lumo",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Lumo",
            path: "Sources/Lumo",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
            ]
        )
    ]
)
