import Foundation

enum LockState: Equatable {
    case idle
    case awaitingPermission         // polling for AX grant before arming
    case arming(remaining: Int)     // 3-2-1 countdown before lock activates
    case locked(remaining: TimeInterval)
    case unlocking
}
