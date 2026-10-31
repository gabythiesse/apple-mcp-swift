// swift-tools-version:5.9
// Module partagé par safari-mcp et computer-mcp : Accessibilité (AXUIElement), vrais événements (CGEvent),
// premier plan, fenêtres de dialogue. Aucune dépendance, aucune autorisation propre (celles du lanceur AppleMCP).
import PackageDescription

let package = Package(
    name: "MacUI",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MacUI", targets: ["MacUI"])],
    targets: [.target(name: "MacUI", path: "Sources/MacUI")]
)
