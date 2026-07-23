import Foundation
import SwiftUI
import UIKit
import WebKit

/// A circular avatar that prefers the server image and falls back to the user's initial.
/// All screens share memory and disk caches; cached DiceBear SVG data is rendered by WKWebView.
struct AvatarView: View {
    let url: URL?
    let name: String
    var size: CGFloat = 40

    @State private var image: UIImage?
    @State private var svgData: Data?

    var body: some View {
        Group {
            if let url, let svgData {
                SVGImageView(data: svgData, baseURL: url)
                    .background(Color(.tertiarySystemFill))
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url) {
            await loadAvatar()
        }
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(Color(.tertiarySystemFill))
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private func loadAvatar() async {
        image = nil
        svgData = nil
        guard let url,
              let data = await AvatarResourceCache.shared.data(for: url),
              !Task.isCancelled
        else {
            return
        }

        if url.path.lowercased().hasSuffix(".svg") {
            svgData = data
        } else {
            image = UIImage(data: data)
        }
    }
}

/// Renders cached SVG data in a transparent WKWebView with interaction and scrolling disabled.
private struct SVGImageView: UIViewRepresentable {
    let data: Data
    let baseURL: URL

    final class Coordinator {
        var loadedURL: URL?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != baseURL else { return }
        context.coordinator.loadedURL = baseURL

        let encodedSVG = data.base64EncodedString()
        let html = """
        <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="margin:0;background:transparent;">
        <img src="data:image/svg+xml;base64,\(encodedSVG)" style="width:100vw;height:100vh;object-fit:cover;display:block;">
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: baseURL.deletingLastPathComponent())
    }
}

/// Shared avatar bytes cache. URLCache provides persistence between launches,
/// while NSCache avoids repeated disk reads during a session.
private actor AvatarResourceCache {
    static let shared = AvatarResourceCache()

    private let memoryCache: NSCache<NSURL, NSData>
    private let diskCache: URLCache
    private var inFlight: [URL: Task<CachedURLResponse?, Never>] = [:]

    private init() {
        let memoryCache = NSCache<NSURL, NSData>()
        memoryCache.totalCostLimit = 32 * 1024 * 1024
        self.memoryCache = memoryCache
        diskCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            diskPath: "workavera-avatars"
        )
    }

    func data(for url: URL) async -> Data? {
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached as Data
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 30

        if let cached = diskCache.cachedResponse(for: request) {
            storeInMemory(cached.data, for: url)
            return cached.data
        }

        if let existing = inFlight[url] {
            return await finish(existing, for: url, request: request)?.data
        }

        let download = Task<CachedURLResponse?, Never> {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200..<300).contains(httpResponse.statusCode) {
                    return nil
                }
                return CachedURLResponse(
                    response: response,
                    data: data,
                    storagePolicy: .allowed
                )
            } catch {
                return nil
            }
        }
        inFlight[url] = download
        return await finish(download, for: url, request: request)?.data
    }

    private func finish(
        _ task: Task<CachedURLResponse?, Never>,
        for url: URL,
        request: URLRequest
    ) async -> CachedURLResponse? {
        let response = await task.value
        inFlight[url] = nil

        if let response {
            storeInMemory(response.data, for: url)
            diskCache.storeCachedResponse(response, for: request)
        }
        return response
    }

    private func storeInMemory(_ data: Data, for url: URL) {
        memoryCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
    }
}
