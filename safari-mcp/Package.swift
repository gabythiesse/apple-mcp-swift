// swift-tools-version:5.9
import PackageDescription
import Foundation

// Info.plist embarqué dans le binaire : clé d’usage Apple Events (pilotage de Safari)
let infoPlist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Info.plist").path

let package = Package(
    name: "SafariMCP",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SafariMCP",
            path: "Sources/SafariMCP",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist])]
        )
    ]
)
