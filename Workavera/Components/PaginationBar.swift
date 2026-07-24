import SwiftUI

/// A reusable pagination bar with circular navigation buttons and tappable page indicators.
/// It appears only for multiple pages by default; set alwaysVisible for stable layouts.
struct PaginationBar: View {
    let pageCount: Int
    @Binding var page: Int
    var alwaysVisible = false

    var body: some View {
        if alwaysVisible || pageCount > 1 {
            HStack {
                pageButton(icon: "chevron.left", disabled: page <= 0) {
                    page -= 1
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color.accentColor : Color(.systemGray4))
                            .frame(width: index == page ? 18 : 6, height: 6)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) { page = index }
                            }
                    }
                }

                Spacer()

                pageButton(icon: "chevron.right", disabled: page >= pageCount - 1) {
                    page += 1
                }
            }
            // Clamp the current page when a refresh changes the number of pages.
            .onChange(of: pageCount) {
                page = min(page, pageCount - 1)
            }
        }
    }

    private func pageButton(icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(disabled ? Color(.systemGray3) : Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .disabled(disabled)
    }
}

/// Pagination controls for vertically scrolling, server-backed lists.
/// Unlike `PaginationBar`, this presents explicit page context and belongs in
/// the scroll content rather than in a fixed bottom bar.
struct ListPaginationFooter: View {
    let pageCount: Int
    @Binding var page: Int

    var body: some View {
        if pageCount > 1 {
            HStack {
                pageButton(
                    title: "Previous page",
                    systemImage: "chevron.left",
                    disabled: page <= 0
                ) {
                    page -= 1
                }

                Spacer()

                Text("Page \(page + 1) of \(pageCount)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                pageButton(
                    title: "Next page",
                    systemImage: "chevron.right",
                    disabled: page >= pageCount - 1
                ) {
                    page += 1
                }
            }
            .onChange(of: pageCount) {
                page = min(page, max(0, pageCount - 1))
            }
        }
    }

    private func pageButton(
        title: String,
        systemImage: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .disabled(disabled)
        .accessibilityLabel(title)
    }
}
