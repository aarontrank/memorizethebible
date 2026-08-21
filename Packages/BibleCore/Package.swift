// swift-tools-version: 5.9
import PackageDescription

// BibleCore holds every rule the app has to get right: the mask ladder, the
// session engine, mastery/confirmation, and persistence. It is pure Foundation
// with no UI and no I/O beyond a file URL, so all of it is testable from the
// command line — see design doc §14, milestone M5: the confirmation rule must
// be exercisable in under a second, not overnight.
let package = Package(
    name: "BibleCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BibleCore", targets: ["BibleCore"])
    ],
    targets: [
        .target(name: "BibleCore"),
        .testTarget(name: "BibleCoreTests", dependencies: ["BibleCore"]),
    ]
)
