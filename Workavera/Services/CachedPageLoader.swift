import Foundation

enum CachedPageLoader {
    /// Presents any locally cached response first, then always revalidates it
    /// against the server. A cache miss is intentionally silent; the network
    /// operation owns all user-visible loading and error state.
    static func load(
        hasPresentedContent: Bool,
        cache: () async -> Void,
        network: () async -> Void
    ) async {
        if !hasPresentedContent {
            await cache()
        }
        guard !Task.isCancelled else { return }
        await network()
    }
}
