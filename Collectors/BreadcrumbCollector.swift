import Foundation
import UIKit

// MARK: - Breadcrumb Collector
public class BreadcrumbCollector {
    public static let shared = BreadcrumbCollector()

    private var breadcrumbs: [Breadcrumb] = []
    private var maxBreadcrumbs: Int = 50
    private let queue = DispatchQueue(label: "com.devskin.breadcrumbs")

    private init() {}

    public func configure(maxBreadcrumbs: Int) {
        self.maxBreadcrumbs = maxBreadcrumbs
    }

    // MARK: - Add Breadcrumb
    public func add(
        category: String,
        message: String,
        level: BreadcrumbLevel = .info,
        data: [String: Any]? = nil
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let breadcrumb = Breadcrumb(
                category: category,
                message: message,
                level: level,
                timestamp: Date(),
                data: data
            )

            self.breadcrumbs.append(breadcrumb)

            // Trim if exceeds max
            if self.breadcrumbs.count > self.maxBreadcrumbs {
                self.breadcrumbs.removeFirst(self.breadcrumbs.count - self.maxBreadcrumbs)
            }
        }
    }

    // MARK: - Get All Breadcrumbs
    public func getAll() -> [Breadcrumb] {
        var result: [Breadcrumb] = []
        queue.sync {
            result = breadcrumbs
        }
        return result
    }

    // MARK: - Clear Breadcrumbs
    public func clear() {
        queue.async { [weak self] in
            self?.breadcrumbs.removeAll()
        }
    }

    // MARK: - Convenience Methods
    public func navigation(from: String, to: String) {
        add(
            category: "navigation",
            message: "Navigated from \(from) to \(to)",
            level: .info,
            data: ["from": from, "to": to]
        )
    }

    public func userAction(_ action: String, element: String? = nil, screen: String? = nil) {
        var data: [String: Any] = ["action": action]
        if let element = element { data["element"] = element }
        if let screen = screen { data["screen"] = screen }

        add(
            category: "user.action",
            message: "User \(action)",
            level: .info,
            data: data
        )
    }

    public func networkRequest(url: String, method: String, statusCode: Int?, duration: TimeInterval) {
        let status = statusCode.map { String($0) } ?? "failed"
        add(
            category: "http",
            message: "\(method) \(url) - \(status)",
            level: statusCode != nil && statusCode! < 400 ? .info : .error,
            data: [
                "url": url,
                "method": method,
                "statusCode": statusCode as Any,
                "duration": duration
            ]
        )
    }

    public func appLifecycle(_ event: String) {
        add(
            category: "app.lifecycle",
            message: event,
            level: .info
        )
    }

    public func log(message: String, level: BreadcrumbLevel = .debug) {
        add(category: "console", message: message, level: level)
    }

    public func error(_ error: Error, context: String? = nil) {
        add(
            category: "error",
            message: error.localizedDescription,
            level: .error,
            data: [
                "type": String(describing: type(of: error)),
                "context": context as Any
            ]
        )
    }
}

// MARK: - Auto Breadcrumb Tracking
public class AutoBreadcrumbTracker {
    public static func startTracking() {
        // Track app lifecycle
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            BreadcrumbCollector.shared.appLifecycle("App became active")
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            BreadcrumbCollector.shared.appLifecycle("App will resign active")
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            BreadcrumbCollector.shared.appLifecycle("App entered background")
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            BreadcrumbCollector.shared.appLifecycle("App will enter foreground")
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            BreadcrumbCollector.shared.add(
                category: "device",
                message: "Memory warning received",
                level: .warning
            )
        }

        // Track orientation changes
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let orientation = UIDevice.current.orientation
            let orientationName: String
            switch orientation {
            case .portrait: orientationName = "portrait"
            case .portraitUpsideDown: orientationName = "portrait_upside_down"
            case .landscapeLeft: orientationName = "landscape_left"
            case .landscapeRight: orientationName = "landscape_right"
            case .faceUp: orientationName = "face_up"
            case .faceDown: orientationName = "face_down"
            default: orientationName = "unknown"
            }

            BreadcrumbCollector.shared.add(
                category: "device",
                message: "Orientation changed to \(orientationName)",
                level: .info,
                data: ["orientation": orientationName]
            )
        }
    }
}
