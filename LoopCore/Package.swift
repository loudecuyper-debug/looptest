// swift-tools-version:5.9
// LoopCore: het plan-brein van LoopApp. Pure logica (enkel Foundation),
// los van GPS, audio en schermen, zodat GitHub Actions alles kan testen.
import PackageDescription

let package = Package(
    name: "LoopCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "LoopCore", targets: ["LoopCore"]),
        .executable(name: "plan-preview", targets: ["PlanPreview"])
    ],
    targets: [
        .target(name: "LoopCore"),
        .executableTarget(name: "PlanPreview", dependencies: ["LoopCore"]),
        .testTarget(name: "LoopCoreTests", dependencies: ["LoopCore"])
    ]
)
