import SwiftUI

/// 通用分页栏：两侧圆形翻页按钮 + 中间胶囊圆点指示器，圆点可点击跳页。
/// 默认只有多页时渲染；需要稳定布局的页面可设置 alwaysVisible。
struct PaginationBar: View {
    let pageCount: Int
    @Binding var page: Int
    var alwaysVisible = false

    var body: some View {
        if alwaysVisible || pageCount > 1 {
            HStack {
                pageButton(icon: "chevron.left", disabled: page <= 0) {
                    page -= 1
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color.accentColor : Color(.systemGray4))
                            .frame(width: index == page ? 18 : 6, height: 6)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) { page = index }
                            }
                    }
                }

                Spacer()

                pageButton(icon: "chevron.right", disabled: page >= pageCount - 1) {
                    page += 1
                }
            }
            // 页数变化（如刷新后数据量改变）时收敛当前页
            .onChange(of: pageCount) {
                page = min(page, pageCount - 1)
            }
        }
    }

    private func pageButton(icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(disabled ? Color(.systemGray3) : Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .disabled(disabled)
    }
}
