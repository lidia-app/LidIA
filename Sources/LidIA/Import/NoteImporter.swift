import Foundation
import SwiftData

enum NoteImporter {
    struct ImportResult: Sendable {
        let imported: Int
        let skipped: Int
        let errors: [String]
    }

    /// Import .md, .mdx, and .txt files as Meeting records.
    @MainActor
    static func importFiles(_ urls: [URL], into context: ModelContext) -> ImportResult {
        var imported = 0
        var skipped = 0
        var errors: [String] = []

        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ext == "md" || ext == "mdx" || ext == "txt" else {
                skipped += 1
                continue
            }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let meeting = parseMeeting(
                    from: content,
                    filename: url.deletingPathExtension().lastPathComponent,
                    fileDate: fileModificationDate(url)
                )
                context.insert(meeting)
                imported += 1
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        try? context.save()
        return ImportResult(imported: imported, skipped: skipped, errors: errors)
    }

    /// Parse a markdown/text file into a Meeting.
    private static func parseMeeting(from content: String, filename: String, fileDate: Date) -> Meeting {
        var title = filename
        var body = content
        var date = fileDate

        // Try to parse YAML frontmatter
        if content.hasPrefix("---") {
            let parts = content.split(separator: "---", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count >= 3 {
                let yaml = String(parts[1])
                body = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)

                // Extract title
                if let range = yaml.range(of: #"title:\s*"?(.+?)"?\s*$"#, options: .regularExpression) {
                    let raw = String(yaml[range])
                    let value = raw.replacingOccurrences(of: #"title:\s*"?"#, with: "", options: .regularExpression)
                        .replacingOccurrences(of: "\"", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { title = value }
                }

                // Extract date
                if let range = yaml.range(of: #"date:\s*(.+)$"#, options: .regularExpression) {
                    let raw = String(yaml[range])
                    let value = raw.replacingOccurrences(of: #"date:\s*"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                    if let parsed = ISO8601DateFormatter().date(from: value) {
                        date = parsed
                    }
                }
            }
        } else if let firstLine = content.split(separator: "\n", maxSplits: 1).first {
            // Use first heading as title
            let heading = String(firstLine).trimmingCharacters(in: .whitespaces)
            if heading.hasPrefix("#") {
                title = heading.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
                body = String(content.split(separator: "\n", maxSplits: 1).dropFirst().joined(separator: "\n"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let meeting = Meeting(title: title, date: date, summary: body, status: .complete)
        return meeting
    }

    private static func fileModificationDate(_ url: URL) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date()
    }
}
