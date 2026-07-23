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
