import Foundation

/// A fixed wall-clock login window. App switching never renews it.
/// No authorization codes, PKCE verifier or browser state are persisted here.
public struct OAuthSessionWindow: Sendable {
    public enum Failure: Error { case invalidTimeout, expired }
    public static let maximumTimeout: Duration = .seconds(600)
    public let expiresAt: Date

    public init(startedAt: Date = Date(), timeout: Duration = OAuthSessionWindow.maximumTimeout) throws {
        guard timeout > .zero, timeout <= Self.maximumTimeout else { throw Failure.invalidTimeout }
        let parts = timeout.components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
        expiresAt = startedAt.addingTimeInterval(seconds)
    }
    public func validate(now: Date = Date()) throws {
        guard now < expiresAt else { throw Failure.expired }
    }
}
