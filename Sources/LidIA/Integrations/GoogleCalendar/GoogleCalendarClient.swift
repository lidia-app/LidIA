import Foundation

actor GoogleCalendarClient {
    private let oauth: GoogleOAuth
    private let baseURL = "https://www.googleapis.com/calendar/v3"

    init(oauth: GoogleOAuth) {
        self.oauth = oauth
    }

    struct CalendarEvent: Sendable, Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let attendees: [String]
        let meetingLink: URL?
        let colorHex: String?
    }

    func listUpcomingEvents(maxResults: Int = 5) async throws -> [CalendarEvent] {
        let token = try await oauth.validAccessToken()
        let now = ISO8601DateFormatter().string(from: Date())
        // Look ahead 2 days for upcoming meetings
        let futureDate = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        let timeMax = ISO8601DateFormatter().string(from: futureDate)

        var components = URLComponents(string: "\(baseURL)/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: now),
            URLQueryItem(name: "timeMax", value: timeMax),
            // Fetch more than needed so we can filter down to real meetings
            URLQueryItem(name: "maxResults", value: "\(maxResults * 4)"),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
        ]

        let data = try await authenticatedRequest(url: components.url!, token: token)
        let allEvents = try parseEvents(from: data, colorMap: nil)
        // Filter to real meetings: must have attendees or a meeting link
        let meetings = allEvents.filter { !$0.attendees.isEmpty || $0.meetingLink != nil }
        return Array(meetings.prefix(maxResults))
    }

    func listEventsForDateRange(from start: Date, to end: Date, maxResults: Int = 50, colorMap: [String: String]? = nil) async throws -> [CalendarEvent] {
        let token = try await oauth.validAccessToken()
        let formatter = ISO8601DateFormatter()
        let timeMin = formatter.string(from: start)
        let timeMax = formatter.string(from: end)

        var components = URLComponents(string: "\(baseURL)/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "maxResults", value: "\(maxResults)"),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
        ]

        let data = try await authenticatedRequest(url: components.url!, token: token)
        return try parseEvents(from: data, colorMap: colorMap)
    }

    func fetchEventColors() async throws -> [String: String] {
        let token = try await oauth.validAccessToken()
        let url = URL(string: "\(baseURL)/colors")!
        let data = try await authenticatedRequest(url: url, token: token)
        let response = try JSONDecoder().decode(ColorsResponse.self, from: data)
        var map: [String: String] = [:]
        for (key, value) in response.event ?? [:] {
            map[key] = value.background
        }
        return map
    }

    private struct ColorsResponse: Codable {
        let event: [String: ColorEntry]?

        struct ColorEntry: Codable {
            let background: String?
        }
    }

    // MARK: - Authenticated Request with 401 Retry

    private func authenticatedRequest(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let preparedRequest = request

        let (data, response) = try await withRetry {
            try await URLSession.shared.data(for: preparedRequest)
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            // Token expired — refresh and retry once
            try await oauth.refreshAccessToken()
            let newToken = try await oauth.validAccessToken()
            var retryRequest = request
            retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            let preparedRetryRequest = retryRequest
            let (retryData, retryResponse) = try await withRetry {
                try await URLSession.shared.data(for: preparedRetryRequest)
            }
            try validateResponse(retryResponse, data: retryData)
            return retryData
        }

        try validateResponse(response, data: data)
        return data
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CalendarError.httpError(statusCode: httpResponse.statusCode, message: body)
        }
    }

    // MARK: - Parsing

    private struct EventsResponse: Codable {
        let items: [EventItem]?
    }

    private struct EventItem: Codable {
        let id: String?
        let summary: String?
        let start: EventDateTime?
        let end: EventDateTime?
        let attendees: [Attendee]?
        let hangoutLink: String?
        let location: String?
        let description: String?
        let colorId: String?

        struct EventDateTime: Codable {
            let dateTime: String?
            let date: String?
        }

        struct Attendee: Codable {
            let email: String?
            let displayName: String?
        }
    }

    private func parseEvents(from data: Data, colorMap: [String: String]?) throws -> [CalendarEvent] {
        let response = try JSONDecoder().decode(EventsResponse.self, from: data)
        return (response.items ?? []).compactMap { parseEventItem($0, colorMap: colorMap) }
    }

    private func parseEventItem(_ item: EventItem, colorMap: [String: String]? = nil) -> CalendarEvent? {
        guard let id = item.id,
              let title = item.summary else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        let start: Date = item.start?.dateTime.flatMap {
            formatter.date(from: $0) ?? fallbackFormatter.date(from: $0)
        } ?? Date()

        let end: Date = item.end?.dateTime.flatMap {
            formatter.date(from: $0) ?? fallbackFormatter.date(from: $0)
        } ?? Date()

        let attendees = (item.attendees ?? []).compactMap { attendee -> String? in
            guard let email = attendee.email else { return attendee.displayName }
            if let displayName = attendee.displayName, !displayName.isEmpty {
                return "\(displayName) <\(email)>"
            }
            return email
        }

        // Extract meeting link from hangoutLink, location, or description
        let meetingLink = extractMeetingLink(
            hangoutLink: item.hangoutLink,
            location: item.location,
            description: item.description
        )

        let colorHex = item.colorId.flatMap { colorMap?[$0] }

        return CalendarEvent(
            id: id,
            title: title,
            start: start,
            end: end,
            attendees: attendees,
            meetingLink: meetingLink,
            colorHex: colorHex
        )
    }

    private func extractMeetingLink(hangoutLink: String?, location: String?, description: String?) -> URL? {
        // Priority: Google Meet link > URL in location > URL in description
        if let link = hangoutLink, let url = URL(string: link) {
            return url
        }

        let meetingPatterns = [
            "https?://[a-z]+\\.zoom\\.us/[^\\s\"<>]+",
            "https?://meet\\.google\\.com/[^\\s\"<>]+",
            "https?://teams\\.microsoft\\.com/[^\\s\"<>]+",
            "https?://[a-z]+\\.slack\\.com/[^\\s\"<>]+",
        ]
        let combined = meetingPatterns.joined(separator: "|")

        for text in [location, description] {
            guard let text else { continue }
            if let range = text.range(of: combined, options: .regularExpression),
               let url = URL(string: String(text[range])) {
                return url
            }
        }
        return nil
    }

    // MARK: - Errors

    enum CalendarError: Error, LocalizedError {
        case invalidEvent
        case httpError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidEvent: "Invalid calendar event data."
            case .httpError(let code, let msg): "Calendar API HTTP \(code): \(msg)"
            }
        }
    }
}
