import Foundation

/// Value object representing account identity information for an AI provider.
/// Encapsulates email, organization, and login method with derived display logic.
public struct AccountInfo: Sendable, Equatable {
    public let email: String?
    public let organization: String?
    public let loginMethod: String?

    public init(
        email: String? = nil,
        organization: String? = nil,
        loginMethod: String? = nil
    ) {
        self.email = email
        self.organization = organization
        self.loginMethod = loginMethod
    }

    /// The best available name for display: email first, then organization.
    public var displayName: String? {
        email ?? organization
    }

    /// Whether this account info has no useful data.
    public var isEmpty: Bool {
        email == nil && organization == nil
    }

    /// The uppercased first character of the display name, for avatar circles.
    public var initialLetter: String? {
        displayName?.first.map { String($0).uppercased() }
    }
}
