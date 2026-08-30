// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotificationManagerCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "NotificationManagerDomain", targets: ["NotificationManagerDomain"]),
        .library(name: "NotificationManagerApplication", targets: ["NotificationManagerApplication"]),
        .library(name: "NotificationManagerPersistence", targets: ["NotificationManagerPersistence"]),
        .library(
            name: "NotificationManagerWidgetSupport",
            targets: ["NotificationManagerWidgetSupport"]
        )
    ],
    targets: [
        .target(name: "NotificationManagerDomain"),
        .target(name: "NotificationManagerApplication", dependencies: ["NotificationManagerDomain"]),
        .target(
            name: "NotificationManagerPersistence",
            dependencies: ["NotificationManagerDomain", "NotificationManagerApplication"]
        ),
        .target(name: "NotificationManagerWidgetSupport"),
        .testTarget(
            name: "NotificationManagerDomainTests",
            dependencies: ["NotificationManagerDomain"]
        ),
        .testTarget(
            name: "NotificationManagerPersistenceTests",
            dependencies: ["NotificationManagerPersistence"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "NotificationManagerApplicationTests",
            dependencies: ["NotificationManagerApplication"]
        ),
        .testTarget(
            name: "NotificationManagerWidgetSupportTests",
            dependencies: ["NotificationManagerWidgetSupport"]
        )
    ]
)
