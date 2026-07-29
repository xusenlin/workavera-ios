import SwiftUI
import WebKit

/// A read-only HTML renderer with JavaScript and in-document anchors.
/// It fills the screen and owns its scrolling, so a document with sticky elements
/// of its own has a full viewport to lay them out against. External links are blocked.
struct HTMLView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.isDirectionalLockEnabled = true
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(Self.wrapped(html), baseURL: nil)
    }

    /// Wraps the document in base styles for system fonts, color scheme, and full width.
    private static func wrapped(_ html: String) -> String {
        """
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            html, body {
                min-width: 100%;
                overflow-x: auto;
                -webkit-overflow-scrolling: touch;
            }
            body {
                font-family: -apple-system, system-ui, sans-serif;
                font-size: 16px;
                line-height: 1.55;
                margin: 0;
                padding: 0;
                color: #1c1c1e;
                overflow-wrap: break-word;
            }
            img { max-width: 100%; height: auto; }
            table {
                display: block;
                max-width: 100%;
                overflow-x: auto;
                -webkit-overflow-scrolling: touch;
            }
            pre, code {
                font-family: ui-monospace, Menlo, monospace;
                background: rgba(120, 120, 128, 0.12);
                border-radius: 6px;
            }
            pre {
                padding: 10px;
                overflow-x: auto;
                -webkit-overflow-scrolling: touch;
            }
            @media (prefers-color-scheme: dark) {
                body { color: #f2f2f7; }
            }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        /// Allows #anchor navigation within the current document and blocks external pages.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }

            guard let targetURL = navigationAction.request.url,
                  targetURL.fragment != nil else {
                decisionHandler(.cancel)
                return
            }

            if targetURL.scheme == "about" {
                decisionHandler(.allow)
                return
            }

            guard let currentURL = webView.url else {
                decisionHandler(.cancel)
                return
            }
            var targetDocument = URLComponents(url: targetURL, resolvingAgainstBaseURL: false)
            var currentDocument = URLComponents(url: currentURL, resolvingAgainstBaseURL: false)
            targetDocument?.fragment = nil
            currentDocument?.fragment = nil
            decisionHandler(targetDocument == currentDocument ? .allow : .cancel)
        }
    }
}
