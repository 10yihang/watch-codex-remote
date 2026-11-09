import Foundation

/// A temporary system overlay is not evidence that the phone is locked.
/// Only active, protected-data-available state permits the operation to proceed.
public enum RemoteActivityGate {
    public enum State: Equatable, Sendable { case active, inactive, background }
    public enum Decision: Equatable, Sendable {
        case proceed, wait, background, protectedDataUnavailable, inactiveTimedOut
    }
    public static let settlingLimit: Duration = .seconds(5)

    public static func decision(state: State, protectedDataAvailable: Bool,
                                elapsed: Duration) -> Decision {
        if state == .background { return .background }
        guard protectedDataAvailable else { return .protectedDataUnavailable }
        if state == .active { return .proceed }
        return elapsed < settlingLimit ? .wait : .inactiveTimedOut
    }
}
