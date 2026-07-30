import SwiftUI
import UIKit

/// Reports every layout pass, which is when self-sizing cells hand back their
/// real heights and the bottom of the content moves.
final class ChatCollectionView: UICollectionView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// Reports the first touch down, without ever recognising, so it cannot
/// interfere with the scroll view's own gestures or the controls in a row.
///
/// It fires on touch *down* deliberately: a tap that expands a tool card has
/// to be known before the resize it causes reaches layout.
private final class TouchDownReporter: UIGestureRecognizer {
    var onTouchDown: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        state = .failed
        onTouchDown?()
    }
}

/// The chat history, backed by `UICollectionView`.
///
/// A `ScrollView` needs its content size before it can resolve a bottom
/// anchor, and `LazyVStack` only gets there by measuring every row — so
/// opening a long, tool-heavy conversation at the newest message cost the
/// whole history and rendered blank until it finished. A collection view
/// lays out from an estimate and measures a row only when it is about to
/// appear, so landing on the last item costs one screenful no matter how far
/// back the conversation goes.
struct ChatHistoryList: UIViewRepresentable {
    let entries: [ChatHistoryEntry]
    let conversationID: String
    let auth: AuthStore
    let store: ChatStore

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ChatCollectionView {
        let collectionView = ChatCollectionView(
            frame: .zero,
            collectionViewLayout: Self.makeLayout()
        )
        collectionView.onLayout = { [weak collectionView, weak coordinator = context.coordinator] in
            guard let collectionView, let coordinator else { return }
            coordinator.collectionViewDidLayout(collectionView)
        }
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        if #available(iOS 26.0, *) {
            // The composer sits flush under this edge and is opaque, so the
            // fade has nothing to fade into — it just dims the last row.
            collectionView.bottomEdgeEffect.isHidden = true
        }
        let touchDown = TouchDownReporter()
        touchDown.cancelsTouchesInView = false
        touchDown.delaysTouchesBegan = false
        touchDown.delaysTouchesEnded = false
        touchDown.onTouchDown = { [weak coordinator = context.coordinator] in
            coordinator?.readerTookOver()
        }
        collectionView.addGestureRecognizer(touchDown)
        // Replaces the gesture the SwiftUI list needed to dismiss the keyboard.
        collectionView.keyboardDismissMode = .interactive
        collectionView.delegate = context.coordinator
        context.coordinator.configure(collectionView: collectionView, parent: self)
        return collectionView
    }

    func updateUIView(_ collectionView: ChatCollectionView, context: Context) {
        context.coordinator.apply(entries, from: self, to: collectionView)
    }

    private static func makeLayout() -> UICollectionViewLayout {
        // `.estimated` is what keeps this cheap: the layout can place every
        // row arithmetically and only pays for the ones it shows.
        let size = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(80)
        )
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 20,
            leading: 16,
            bottom: 20,
            trailing: 16
        )
        return UICollectionViewCompositionalLayout(section: section)
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate {
        private enum Section { case history }

        private var dataSource: UICollectionViewDiffableDataSource<Section, String>?
        /// Backs the cell provider, which is handed only an identifier.
        private var entriesByID: [String: ChatHistoryEntry] = [:]
        private var conversationID: String?
        private var hasLandedAtBottom = false
        /// True from first content until the reader scrolls; see `collectionViewDidLayout`.
        private var isLanding = false
        /// Streaming only follows the tail while the reader is already there.
        private var isPinnedToBottom = true

        func configure(collectionView: UICollectionView, parent: ChatHistoryList) {
            conversationID = parent.conversationID
            let registration = UICollectionView.CellRegistration<UICollectionViewCell, String> {
                [weak self] cell, _, id in
                guard let self,
                      let entry = entriesByID[id],
                      let conversationID else { return }
                cell.contentConfiguration = UIHostingConfiguration {
                    ChatHistoryEntryView(
                        entry: entry,
                        conversationID: conversationID
                    )
                    .padding(.top, entry.topSpacing)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity, alignment: .center)
                    // Ties per-row state (an expanded disclosure) to the row
                    // it belongs to, so a recycled cell cannot inherit it.
                    .id(entry.id)
                    .environment(parent.auth)
                    .environment(parent.store)
                }
                .margins(.all, 0)
                cell.backgroundConfiguration = .clear()
            }

            dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) {
                collectionView, indexPath, id in
                collectionView.dequeueConfiguredReusableCell(
                    using: registration,
                    for: indexPath,
                    item: id
                )
            }
        }

        func apply(
            _ entries: [ChatHistoryEntry],
            from parent: ChatHistoryList,
            to collectionView: UICollectionView
        ) {
            guard let dataSource else { return }

            if conversationID != parent.conversationID {
                hasLandedAtBottom = false
                isLanding = false
                isPinnedToBottom = true
            }
            conversationID = parent.conversationID

            // Rows whose content moved on need re-rendering; a matching
            // identifier alone would leave the old snapshot on screen.
            let changed = entries
                .filter { entriesByID[$0.id] != nil && entriesByID[$0.id] != $0 }
                .map(\.id)

            entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

            var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
            snapshot.appendSections([.history])
            snapshot.appendItems(entries.map(\.id), toSection: .history)
            if !changed.isEmpty {
                snapshot.reconfigureItems(changed)
            }
            dataSource.apply(snapshot, animatingDifferences: false)

            guard !entries.isEmpty else { return }
            if !hasLandedAtBottom {
                // Held until the reader touches the list: every layout pass
                // re-lands, which is what absorbs the self-sizing settle.
                isLanding = true
                hasLandedAtBottom = true
            }
            if isLanding || isPinnedToBottom {
                scrollToBottom(collectionView, animated: !isLanding)
            }
        }

        /// Self-sizing means the bottom is not known until the rows near it
        /// have been measured, and measuring them moves it again, so the
        /// opening jump repeats on every layout pass until the reader takes
        /// over. Once the offset has stopped moving this is a no-op.
        ///
        /// A settled offset is deliberately *not* the signal to stop: the
        /// first pass often lands where the estimate already put it, and
        /// treating that as settled ends the landing before the rows near the
        /// end have been measured at all.
        func collectionViewDidLayout(_ collectionView: UICollectionView) {
            guard isLanding else { return }
            scrollToBottom(collectionView, animated: false)
        }

        /// From the first touch on, a layout change is the reader's doing —
        /// expanding a tool card resizes its row — and re-landing on it would
        /// yank them to the end.
        func readerTookOver() {
            isLanding = false
        }

        private func scrollToBottom(_ collectionView: UICollectionView, animated: Bool) {
            let count = collectionView.numberOfItems(inSection: 0)
            guard count > 0, collectionView.bounds.height > 0 else { return }
            collectionView.scrollToItem(
                at: IndexPath(item: count - 1, section: 0),
                at: .bottom,
                animated: animated
            )
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            readerTookOver()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard hasLandedAtBottom, !isLanding else { return }
            let distanceFromBottom = scrollView.contentSize.height
                - scrollView.contentOffset.y
                - scrollView.bounds.height
                + scrollView.adjustedContentInset.bottom
            isPinnedToBottom = distanceFromBottom < 60
        }
    }
}
