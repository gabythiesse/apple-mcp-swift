// swift-tools-version:5.9
import PackageDescription
import Foundation

// Info.plist embarqué dans le binaire : clés d'usage Calendriers exigées par macOS pour l'accès EventKit
let infoPlist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Info.plist").path

let package = Package(
    name: "CalendarMCP",
    platforms: [.macOS(.v14)],
    targets: [
        // Petit filet Objective-C : rattrape les exceptions ObjC des appels privés (Swift ne sait pas les attraper)
        .target(name: "Garde", path: "Sources/Garde"),
        .executableTarget(
            name: "CalendarMCP",
            dependencies: ["Garde"],
            path: "Sources/CalendarMCP",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist])]
        )
    ]
)
