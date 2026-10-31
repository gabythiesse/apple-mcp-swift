// swift-tools-version:5.9
import PackageDescription
import Foundation

// Info.plist embarqué dans le binaire : clé d'usage Apple Events (automatisation de Mail)
let infoPlist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Info.plist").path

let package = Package(
    name: "MailMCP",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MailMCP",
            path: "Sources/MailMCP",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist])]
        )
    ]
)
