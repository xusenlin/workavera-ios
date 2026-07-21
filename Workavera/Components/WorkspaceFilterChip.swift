import SwiftUI

struct WorkspaceFilterChip: View {
    let title: String
    let isSelected: Bool
    var systemImage: String?
    var dotColor: Color?
    var count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 7, height: 7)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .medium))
                }

                Text(title)

                if let count {
                    Text("\(count)")
                        .foregroundStyle(isSelected ? .primary : .tertiary)
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            .overlay {
                if isSelected {
                    Capsule()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
