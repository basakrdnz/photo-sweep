// swift-tools-version: 6.0
import PackageDescription

// SweepCore: fotoğraf benzerliği ve öneri mantığı. Apple kütüphanelerine
// (Photos, Vision) bağımlı değil; bu yüzden Linux'ta da test edilebiliyor.
let package = Package(
    name: "SweepCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SweepCore", targets: ["SweepCore"])
    ],
    targets: [
        .target(name: "SweepCore"),
        .testTarget(name: "SweepCoreTests", dependencies: ["SweepCore"]),
    ]
)
