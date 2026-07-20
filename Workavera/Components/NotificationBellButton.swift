import SwiftUI

struct NotificationBellButton: View {
    let unreadCount: Int
    let action: () -> Void

    @State private var isPulsing = false

    var body: some View {
        Button(action: action) {
            Image(systemName: unreadCount > 0 ? "bell.fill" : "bell")
                .overlay(alignment: .topTrailing) {
                    if unreadCount > 0 {
                        Circle()
                            .fill(.red)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                            .scaleEffect(isPulsing ? 1.3 : 0.85)
                            .opacity(isPulsing ? 0.65 : 1)
                            .offset(x: 4, y: -3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(unreadCount > 0 ? "Notifications, \(unreadCount) unread" : "Notifications")
        .onAppear { updatePulse() }
        .onChange(of: unreadCount) { updatePulse() }
    }

    private func updatePulse() {
        guard unreadCount > 0 else {
            isPulsing = false
            return
        }
        isPulsing = false
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}
