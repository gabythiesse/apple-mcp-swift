// swift-tools-version:5.9
import PackageDescription
import Foundation

// Info.plist embarqué dans le binaire (identité du serveur ; les clés d'usage vivent dans celui du lanceur)
let infoPlist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Info.plist").path

let package = Package(
    name: "ComputerMCP",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../shared")],
    targets: [
        .executableTarget(
            name: "ComputerMCP",
            dependencies: [.product(name: "MacUI", package: "shared")],
            path: "Sources/ComputerMCP",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist])]
        )
    ]
)
