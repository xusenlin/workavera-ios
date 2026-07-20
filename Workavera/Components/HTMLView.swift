import SwiftUI
import WebKit

/// 只读 HTML 渲染视图：禁用 JavaScript 与链接跳转，自适应内容高度，
/// 配合外层 ScrollView 滚动（自身不滚动）。支持深色模式。
struct HTMLView: UIViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(Self.wrapped(html), baseURL: nil)
    }

    /// 包一层基础样式：系统字体、跟随深浅色、撑满宽度。
    private static func wrapped(_ html: String) -> String {
        """
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
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
            pre, code {
                font-family: ui-monospace, Menlo, monospace;
                background: rgba(120, 120, 128, 0.12);
                border-radius: 6px;
            }
            pre { padding: 10px; overflow-x: auto; }
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
        private let parent: HTMLView
        var loadedHTML: String?

        init(_ parent: HTMLView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { result, _ in
                guard let height = result as? CGFloat, height > 0 else { return }
                DispatchQueue.main.async {
                    self.parent.contentHeight = height
                }
            }
        }

        /// 只读展示：禁止点击链接跳出。
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
