import SwiftUI

struct InlineErrorBanner: View {
    let message: String
    var actionTitle = "Retry"
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(actionTitle, action: action)
                .font(.footnote.weight(.medium))
        }
        .foregroundStyle(.red)
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct InlineErrorListSection: View {
    let message: String
    var actionTitle = "Retry"
    let action: () -> Void

    var body: some View {
        Section {
            InlineErrorBanner(
                message: message,
                actionTitle: actionTitle,
                action: action
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }
}
