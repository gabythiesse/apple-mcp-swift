// swift-tools-version:5.9
import PackageDescription
import Foundation

// Info.plist embarqué : toutes les clés d'usage des six serveurs, puisque macOS les lit sur le lanceur (processus responsable)
let infoPlist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Info.plist").path

let package = Package(
    name: "AppleMCP",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AppleMCP",
            path: "Sources/AppleMCP",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist])]
        )
    ]
)
