import Foundation
import SwiftUI

@main
struct NotificationManagerApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                Task14UITestFixtureRoot()
            } else {
                Text("Notification Manager")
            }
            #else
            Text("Notification Manager")
            #endif
        }
    }
}
