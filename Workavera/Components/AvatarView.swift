import SwiftUI
import WebKit

/// 圆形头像：优先加载后端真实头像，加载中或无头像时显示姓名首字符。
/// Workavera 的预置头像是 DiceBear 生成的 SVG，UIImage 无法解码，
/// 因此 .svg 文件走 WKWebView 渲染，其余格式走 AsyncImage。
struct AvatarView: View {
    let url: URL?
    let name: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url, url.path.lowercased().hasSuffix(".svg") {
                SVGImageView(url: url)
                    .background(Color(.tertiarySystemFill))
            } else if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
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
}

/// 用 WKWebView 渲染 SVG 图片，透明背景、禁用交互与滚动。
private struct SVGImageView: UIViewRepresentable {
    let url: URL

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
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url

        let html = """
        <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="margin:0;background:transparent;">
        <img src="\(url.absoluteString)" style="width:100vw;height:100vh;object-fit:cover;display:block;">
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
