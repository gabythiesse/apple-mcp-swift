// swift-tools-version:5.9
import PackageDescription
import Foundation

// Info.plist embarqué dans le binaire : clés d'usage Rappels exigées par macOS pour l'accès EventKit
let infoPlist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Info.plist").path

let package = Package(
    name: "RemindersMCP",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RemindersMCP",
            path: "Sources/RemindersMCP",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist])]
        )
    ]
)
