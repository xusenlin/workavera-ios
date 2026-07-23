import SwiftUI

extension UserStatus {
    var color: Color {
        switch self {
        case .online: .green
        case .away: .yellow
        case .busy: .red
        case .offline: .gray
        }
    }
}

/// A colored presence-status dot.
struct StatusDot: View {
    let status: UserStatus
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
    }
}

/// A status label containing a colored dot and text.
struct StatusBadge: View {
    let status: UserStatus

    var body: some View {
        HStack(spacing: 5) {
            StatusDot(status: status)
            Text(status.label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
