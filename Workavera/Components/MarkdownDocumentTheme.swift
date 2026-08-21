import MarkdownUI
import SwiftUI

extension View {
    /// Applies the web reader's presentation to a document body: the type
    /// scale of `.workavera-doc-reader`, plus the shared code block style.
    ///
    /// Chat keeps `workspaceMarkdownCodeStyle()` on its own, the way the web
    /// app leaves chat messages on Streamdown's defaults.
    func workspaceDocumentMarkdownStyle() -> some View {
        // The code style has to sit inside the theme: it writes one block
        // style into whatever theme it inherits, so a theme applied after it
        // would replace the result wholesale.
        self
            .workspaceMarkdownCodeStyle()
            .markdownTheme(.workaveraDocument)
            // MarkdownUI draws every cell edge by default, which reads as a
            // spreadsheet next to the soft, rounded block the web reader and
            // Android both show. Rules between rows are as close as the
            // library gets: the selector that would draw the header rule alone
            // is not constructible outside the module.
            .markdownTableBorderStyle(
                .init(.insideHorizontalBorders, color: .secondary.opacity(0.25))
            )
            .markdownTableBackgroundStyle(
                .alternatingRows(documentTableFill, documentTableFill, header: documentTableFill)
            )
    }
}

extension Theme {
    /// The document type scale the web reader uses (`.workavera-doc-reader`,
    /// itself a restatement of the BlockNote editor's scale), carried over so
    /// a document reads the same on a phone as on the desktop.
    ///
    /// MarkdownUI's own defaults are tuned for chat-sized messages: a full em
    /// of air under every block and headings that barely lift off the text.
    /// A document wants the opposite — blocks packed at 3pt and separated by a
    /// generous line height, with headings doing the work of opening sections.
    ///
    /// Built on `.basic` so tables, which the web scale says nothing about,
    /// keep the library's cell padding.
    static let workaveraDocument =
        Theme.basic
        .text {
            FontSize(16)
        }
        .link {
            ForegroundColor(.accentColor)
            UnderlineStyle(.single)
        }
        .heading1 { documentHeading($0, size: 2) }
        .heading2 { documentHeading($0, size: 1.5) }
        .heading3 { documentHeading($0, size: 1.3) }
        .heading4 { documentHeading($0, size: 1) }
        .heading5 { documentHeading($0, size: 0.9) }
        .heading6 { documentHeading($0, size: 0.8) }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(documentExtraLineSpacing))
                .markdownMargin(top: documentBlockMargin, bottom: documentBlockMargin)
        }
        .list { configuration in
            configuration.label
                .markdownMargin(top: documentBlockMargin, bottom: documentBlockMargin)
        }
        .listItem { configuration in
            configuration.label
                .relativeLineSpacing(.em(documentExtraLineSpacing))
                .markdownMargin(top: documentBlockMargin, bottom: documentBlockMargin)
        }
        .blockquote { configuration in
            configuration.label
                .relativeLineSpacing(.em(documentExtraLineSpacing))
                .relativePadding(.leading, length: .em(1))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 2)
                }
                .markdownMargin(top: documentBlockMargin, bottom: documentBlockMargin)
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .markdownMargin(top: documentBlockMargin, bottom: documentBlockMargin)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.bold)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(documentExtraLineSpacing))
                .relativePadding(.horizontal, length: .em(0.9))
                .relativePadding(.vertical, length: .em(0.6))
        }
        .thematicBreak {
            Divider().markdownMargin(top: 20, bottom: 20)
        }
}

/// The tint the table block sits on, matching the soft rounded block the web
/// reader and the Android renderer both draw behind a table.
private let documentTableFill = Color.secondary.opacity(0.08)

/// The web reader packs blocks at 3px and lets the line height carry the
/// rhythm, rather than spacing paragraphs a full line apart.
private let documentBlockMargin: CGFloat = 3

/// SwiftUI's line spacing is the air *added* to a line box, where CSS
/// `line-height` is the whole box. The system font lays out at roughly 1.2, so
/// the web reader's 1.6 is about 0.4em of extra spacing here.
private let documentExtraLineSpacing: CGFloat = 0.4

/// Headings share the web reader's weight, tight leading, and the 1.125rem of
/// air above that separates a section from the block before it.
private func documentHeading(
    _ configuration: BlockConfiguration,
    size: CGFloat
) -> some View {
    configuration.label
        .relativeLineSpacing(.em(0.05))
        .markdownMargin(top: .rem(1.125), bottom: .em(0.4))
        .markdownTextStyle {
            FontWeight(.bold)
            FontSize(.em(size))
        }
}
