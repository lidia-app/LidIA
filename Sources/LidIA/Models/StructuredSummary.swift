import Foundation

struct StructuredSummary: Codable, Sendable {
    var title: String
    var sections: [SummarySection]
    var decisions: [String]
    var actionItems: [SummaryActionItem]

    struct SummarySection: Codable, Sendable, Identifiable {
        var id: String { heading }
        var heading: String
        var bullets: [SummaryBullet]
    }

    struct SummaryBullet: Codable, Sendable, Identifiable {
        let id: UUID
        var text: String
        var sourceQuote: String?

        init(text: String, sourceQuote: String? = nil) {
            self.id = UUID()
            self.text = text
            self.sourceQuote = sourceQuote
        }

        enum CodingKeys: String, CodingKey {
            case text
            case sourceQuote = "source_quote"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = UUID()
            self.text = try container.decode(String.self, forKey: .text)
            self.sourceQuote = try container.decodeIfPresent(String.self, forKey: .sourceQuote)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(sourceQuote, forKey: .sourceQuote)
        }
    }

    struct SummaryActionItem: Codable, Sendable {
        var title: String
        var assignee: String?
        var deadline: String?
        var sourceQuote: String?

        enum CodingKeys: String, CodingKey {
            case title, assignee, deadline
            case sourceQuote = "source_quote"
        }
    }

    /// Convert to flat markdown for backward compatibility.
    var markdownSummary: String {
        var lines: [String] = []
        for section in sections {
            lines.append("### \(section.heading)")
            for bullet in section.bullets {
                lines.append("- \(bullet.text)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
