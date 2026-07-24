import Foundation
import MarkdownUI
import SwiftUI
import UIKit

extension View {
    /// Applies the shared Workavera presentation for fenced Markdown code blocks.
    func workspaceMarkdownCodeStyle() -> some View {
        markdownBlockStyle(\.codeBlock) { configuration in
            MarkdownCodeBlockView(configuration: configuration)
        }
        .markdownCodeSyntaxHighlighter(WorkspaceCodeHighlighter())
    }
}

/// Fenced code block with a language tag, copy button, monospaced content,
/// and a theme-aware gray surface. Horizontally scrollable for long lines.
private struct MarkdownCodeBlockView: View {
    let configuration: CodeBlockConfiguration

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(languageLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Color.green : Color.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .relativeLineSpacing(.em(0.2))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.88))
                    }
                    .padding(12)
            }
        }
        .background(Color(.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .markdownMargin(bottom: 12)
    }

    private var languageLabel: String {
        let language = configuration.language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return language.isEmpty ? "code" : language.lowercased()
    }

    private func copy() {
        UIPasteboard.general.string = configuration.content
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { copied = false }
        }
    }
}

/// Lightweight, dependency-free syntax colorizer for common language tokens.
private struct WorkspaceCodeHighlighter: CodeSyntaxHighlighter {
    func highlightCode(_ code: String, language: String?) -> Text {
        CodeColoring.segments(of: code).reduce(Text("")) { partial, segment in
            let piece = Text(segment.text)
            return partial + (segment.color.map { piece.foregroundColor($0) } ?? piece)
        }
    }
}

private enum CodeColoring {
    struct Segment {
        let text: String
        let color: Color?
    }

    private static let keywords = [
        "func", "function", "def", "fn", "return", "let", "var", "const", "val",
        "class", "struct", "enum", "interface", "protocol", "extension", "import",
        "export", "from", "package", "namespace", "if", "else", "elif", "for",
        "while", "do", "switch", "case", "break", "continue", "default", "guard",
        "defer", "try", "catch", "throw", "throws", "finally", "async", "await",
        "yield", "public", "private", "protected", "internal", "static", "final",
        "abstract", "override", "new", "self", "this", "super", "nil", "null",
        "true", "false", "void", "in", "is", "as", "typeof", "instanceof",
        "lambda", "where", "pub", "impl", "trait", "match", "mut", "use",
    ].joined(separator: "|")

    private static let regex: NSRegularExpression? = {
        let pattern = #"(?<comment>//[^\n]*|#[^\n]*|/\*[\s\S]*?\*/)|(?<string>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`)|(?<number>\b0x[0-9a-fA-F]+\b|\b\d[\d_]*\.?\d*\b)|(?<keyword>\b(?:\#(keywords))\b)"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    static func segments(of code: String) -> [Segment] {
        guard let regex else { return [Segment(text: code, color: nil)] }
        let ns = code as NSString
        var segments: [Segment] = []
        var cursor = 0

        regex.enumerateMatches(in: code, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            let range = match.range
            if range.location > cursor {
                let plain = ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
                segments.append(Segment(text: plain, color: nil))
            }
            segments.append(Segment(text: ns.substring(with: range), color: color(for: match)))
            cursor = range.location + range.length
        }

        if cursor < ns.length {
            segments.append(Segment(text: ns.substring(from: cursor), color: nil))
        }
        return segments
    }

    private static func color(for match: NSTextCheckingResult) -> Color? {
        if match.range(withName: "comment").location != NSNotFound { return SyntaxColor.comment }
        if match.range(withName: "string").location != NSNotFound { return SyntaxColor.string }
        if match.range(withName: "number").location != NSNotFound { return SyntaxColor.number }
        if match.range(withName: "keyword").location != NSNotFound { return SyntaxColor.keyword }
        return nil
    }
}

/// Xcode-like token colors that adapt to light and dark appearances.
private enum SyntaxColor {
    static let keyword = dynamic(light: (0.61, 0.12, 0.55), dark: (0.94, 0.47, 0.71))
    static let string = dynamic(light: (0.77, 0.20, 0.18), dark: (0.98, 0.60, 0.54))
    static let number = dynamic(light: (0.11, 0.35, 0.80), dark: (0.60, 0.80, 1.00))
    static let comment = dynamic(light: (0.42, 0.48, 0.44), dark: (0.50, 0.58, 0.55))

    private static func dynamic(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(UIColor { trait in
            let rgb = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}
