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

/// 状态圆点。
struct StatusDot: View {
    let status: UserStatus
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
    }
}

/// 圆点 + 文案的状态标签。
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
