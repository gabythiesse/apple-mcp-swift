// swift-tools-version:5.9
import PackageDescription
import Foundation

// Info.plist embarqué dans le binaire : clé d’usage Apple Events (pilotage de Safari)
let infoPlist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Info.plist").path

let package = Package(
    name: "SafariMCP",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../shared")],   // MacUI : Accessibilité, vrais événements, premier plan, dialogues (commun avec computer-mcp)
    targets: [
        .executableTarget(
            name: "SafariMCP",
            dependencies: [.product(name: "MacUI", package: "shared")],
            path: "Sources/SafariMCP",
            resources: [.embedInCode("Resources/mcp.js")],   // bibliothèque injectée dans les pages, embarquée dans le binaire
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist])]
        )
    ]
)
