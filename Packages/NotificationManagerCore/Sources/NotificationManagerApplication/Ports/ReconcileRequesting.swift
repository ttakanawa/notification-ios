import Foundation

public enum ReconcileReason: Sendable, Equatable, Hashable {
    case reminderSaved(UUID)
    case reminderDeleted(UUID)
    case modelChanged
    case deviceSettingsChanged
    case foreground
}

public protocol ReconcileRequesting: Sendable {
    func requestReconcile(_ reason: ReconcileReason) async
}
