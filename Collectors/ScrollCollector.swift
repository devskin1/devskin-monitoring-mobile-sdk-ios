import UIKit

// MARK: - Scroll Collector for Scroll Depth Tracking
public class ScrollCollector {
    public static let shared = ScrollCollector()

    private var isEnabled = false
    private var currentScreen: String = ""
    private var maxScrollDepth: [String: Int] = [:]
    private var scrollStartY: CGFloat = 0

    private init() {}

    public func enable() {
        isEnabled = true
    }

    public func disable() {
        isEnabled = false
    }

    public func setCurrentScreen(_ name: String) {
        currentScreen = name
        // Reset max scroll depth for new screen
        maxScrollDepth[name] = 0
    }

    // MARK: - Track Scroll
    public func trackScroll(
        scrollView: UIScrollView,
        contentHeight: CGFloat? = nil,
        viewportHeight: CGFloat? = nil
    ) {
        guard isEnabled, !currentScreen.isEmpty else { return }

        let scrollY = scrollView.contentOffset.y
        let actualContentHeight = contentHeight ?? scrollView.contentSize.height
        let actualViewportHeight = viewportHeight ?? scrollView.bounds.height

        // Calculate scroll depth percentage
        let maxScrollY = actualContentHeight - actualViewportHeight
        guard maxScrollY > 0 else { return }

        let scrollDepth = min(100, Int((scrollY / maxScrollY) * 100))

        // Only record if scrolled further
        let previousMax = maxScrollDepth[currentScreen] ?? 0
        guard scrollDepth > previousMax else {
            scrollStartY = scrollY
            return
        }

        maxScrollDepth[currentScreen] = scrollDepth

        let direction = scrollY > scrollStartY ? "down" : "up"

        let scrollData = ScrollData(
            screenName: currentScreen,
            scrollDepth: scrollDepth,
            maxScrollDepth: scrollDepth,
            contentHeight: actualContentHeight,
            viewportHeight: actualViewportHeight,
            direction: direction,
            timestamp: Date()
        )

        MobileTransport.shared.sendScrollData(scrollData)
        scrollStartY = scrollY
    }

    // MARK: - Track ScrollView Delegate
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        trackScroll(scrollView: scrollView)
    }

    // MARK: - Get Max Scroll Depth for Screen
    public func getMaxScrollDepth(for screenName: String) -> Int {
        return maxScrollDepth[screenName] ?? 0
    }

    // MARK: - Reset
    public func reset() {
        maxScrollDepth.removeAll()
    }
}

// MARK: - UIScrollView Extension
public extension UIScrollView {
    func trackScrollDepth(screenName: String? = nil) {
        if let screenName = screenName {
            ScrollCollector.shared.setCurrentScreen(screenName)
        }
        ScrollCollector.shared.trackScroll(scrollView: self)
    }
}

// MARK: - UITableView Scroll Tracking
public class TrackedTableViewDelegate: NSObject, UITableViewDelegate {
    private weak var originalDelegate: UITableViewDelegate?
    private let screenName: String

    public init(originalDelegate: UITableViewDelegate?, screenName: String) {
        self.originalDelegate = originalDelegate
        self.screenName = screenName
        super.init()
        ScrollCollector.shared.setCurrentScreen(screenName)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        ScrollCollector.shared.scrollViewDidScroll(scrollView)
        originalDelegate?.scrollViewDidScroll?(scrollView)
    }

    // Forward other delegate methods to original
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        originalDelegate?.tableView?(tableView, didSelectRowAt: indexPath)
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return originalDelegate?.tableView?(tableView, heightForRowAt: indexPath) ?? UITableView.automaticDimension
    }
}

// MARK: - UICollectionView Scroll Tracking
public class TrackedCollectionViewDelegate: NSObject, UICollectionViewDelegate {
    private weak var originalDelegate: UICollectionViewDelegate?
    private let screenName: String

    public init(originalDelegate: UICollectionViewDelegate?, screenName: String) {
        self.originalDelegate = originalDelegate
        self.screenName = screenName
        super.init()
        ScrollCollector.shared.setCurrentScreen(screenName)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        ScrollCollector.shared.scrollViewDidScroll(scrollView)
        originalDelegate?.scrollViewDidScroll?(scrollView)
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        originalDelegate?.collectionView?(collectionView, didSelectItemAt: indexPath)
    }
}
