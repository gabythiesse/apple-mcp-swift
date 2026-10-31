// swift-tools-version:5.9
import PackageDescription
import Foundation

// Info.plist embarqué dans le lanceur : clés d'usage Contacts et Automatisation exigées par macOS
let infoPlist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Info.plist").path

let package = Package(
    name: "ContactsMCP",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ContactsMCP", targets: ["ContactsMCP"]),
        .library(name: "ContactsMCPCore", type: .dynamic, targets: ["ContactsMCPCore"]),
    ],
    targets: [
        // Lanceur stable (identité des autorisations macOS) : charge la bibliothèque par dlopen, sans dépendance de lien
        .executableTarget(
            name: "ContactsMCP",
            path: "Sources/ContactsMCP",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist])]
        ),
        .target(name: "ContactsMCPCore", path: "Sources/ContactsMCPCore"),
    ]
)
