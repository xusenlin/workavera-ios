import SwiftUI

/// 未实现模块的占位页。
struct PlaceholderView: View {
    let section: AppSection

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: section.icon)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 110, height: 110)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 26, style: .continuous))

            VStack(spacing: 10) {
                Text(section.title)
                    .font(.title2.bold())
                Text(section.placeholderDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
            }

            Text("Coming soon")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: Capsule())

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
