// swift-tools-version:5.9
import PackageDescription
import Foundation

// Info.plist embarqué dans le binaire : identité stable et clé d'usage Automatisation (pilotage de Notes)
let infoPlist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Info.plist").path

let package = Package(
    name: "NotesMCP",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotesMCP",
            path: "Sources/NotesMCP",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist])]
        )
    ]
)
