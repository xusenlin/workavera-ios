import SwiftUI

struct CachedContentView<Content: View>: View {
    let isLoading: Bool
    let hasLoaded: Bool
    let loadingTitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if isLoading && !hasLoaded {
                ProgressView(loadingTitle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content()
            }
        }
    }
}
