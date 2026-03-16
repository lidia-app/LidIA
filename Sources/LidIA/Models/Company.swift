import Foundation

/// Groups meeting attendees by email domain for company-level insights.
/// Not a SwiftData model — computed on-the-fly from attendee emails.
struct Company: Identifiable, Hashable {
    var id: String { domain }
    let domain: String
    let name: String  // Derived from domain (e.g., "cloudvisor.eu" -> "Cloudvisor")
    var attendeeEmails: Set<String> = []
    var meetingCount: Int = 0
    var lastMeetingDate: Date?
    var openActionItems: Int = 0

    /// Derive a display name from the domain
    static func displayName(from domain: String) -> String {
        let parts = domain.split(separator: ".")
        guard let first = parts.first else { return domain }
        return String(first).capitalized
    }
}
