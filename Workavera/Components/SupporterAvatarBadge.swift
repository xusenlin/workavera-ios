import SwiftUI

/// A small, celebratory mark for the owner of the current Apple Account.
/// The warm gradient remains legible over both photos and generated avatars.
struct SupporterAvatarBadge: View {
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size * 0.43, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [.yellow, .orange],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(Color(.systemGroupedBackground), lineWidth: max(2, size * 0.12))
            }
            .shadow(color: .orange.opacity(0.3), radius: size * 0.2, y: 1)
            .accessibilityHidden(true)
    }
}
