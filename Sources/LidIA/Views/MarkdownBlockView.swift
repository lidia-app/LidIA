import SwiftUI

/// Renders a markdown string with proper block-level layout:
/// headings, bullet lists (with nesting), and paragraphs.
struct MarkdownBlockView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    // MARK: - Block Model

    private enum Block {
        case heading(level: Int, text: String)
        case bullet(indent: Int, text: String)
        case paragraph(String)
        case blank
    }

    // MARK: - Parser

    private func parseBlocks() -> [Block] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [Block] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .init(charactersIn: " "))

            if trimmed.isEmpty {
                blocks.append(.blank)
                continue
            }

            // Headings: ### Title, ## Title, # Title
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let headingText = String(trimmed.dropFirst(level))
                    .trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: min(level, 4), text: headingText))
                continue
            }

            // Bullets: - text, * text (count leading spaces for indent)
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let bulletText = String(trimmed.dropFirst(2))
                let indent = leadingSpaces / 2
                blocks.append(.bullet(indent: indent, text: bulletText))
                continue
            }

            // Plain text
            blocks.append(.paragraph(trimmed))
        }

        return blocks
    }

    // MARK: - Rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)
                .padding(.top, level <= 2 ? 12 : 8)
                .padding(.bottom, 2)
        case .bullet(let indent, let text):
            bulletView(indent: indent, text: text)
        case .paragraph(let text):
            inlineMarkdown(text)
                .font(.body)
        case .blank:
            Spacer().frame(height: 4)
        }
    }

    private func headingView(level: Int, text: String) -> some View {
        inlineMarkdown(text)
            .font(headingFont(level))
            .foregroundStyle(level <= 2 ? .primary : .primary)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        case 3: .headline
        default: .subheadline.bold()
        }
    }

    private func bulletView(indent: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(indent == 0 ? "\u{2022}" : "\u{25E6}")
                .font(.body)
                .foregroundStyle(.secondary)
            inlineMarkdown(text)
                .font(.body)
        }
        .padding(.leading, CGFloat(indent) * 16)
    }

    private func inlineMarkdown(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }
}
