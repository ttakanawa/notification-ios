import Foundation
import SwiftUI

@main
struct NotificationManagerApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                let scenario = Self.uiScenario
                if ["settings", "data-unavailable", "notification-unavailable"]
                    .contains(scenario)
                {
                    Task15UITestFixtureRoot(scenario: scenario)
                } else {
                    Task14UITestFixtureRoot()
                }
            } else {
                Text("common.app-name")
            }
            #else
            Text("common.app-name")
            #endif
        }
    }

    private static var uiScenario: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui-scenario"),
              arguments.indices.contains(index + 1)
        else {
            return "navigation"
        }
        return arguments[index + 1]
    }
}
