import UIKit

// MARK: - Touch Collector for Heatmap Data
public class TouchCollector {
    public static let shared = TouchCollector()

    private var isEnabled = false
    private var currentScreen: String = ""

    private init() {}

    public func enable() {
        isEnabled = true
        swizzleTouchMethods()
    }

    public func disable() {
        isEnabled = false
    }

    public func setCurrentScreen(_ name: String) {
        currentScreen = name
    }

    // MARK: - Touch Handling
    private func swizzleTouchMethods() {
        let originalSelector = #selector(UIWindow.sendEvent(_:))
        let swizzledSelector = #selector(UIWindow.devskin_sendEvent(_:))

        guard let originalMethod = class_getInstanceMethod(UIWindow.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UIWindow.self, swizzledSelector) else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

// MARK: - UIWindow Extension for Touch Tracking
extension UIWindow {
    @objc func devskin_sendEvent(_ event: UIEvent) {
        // Call original implementation
        devskin_sendEvent(event)

        // Track touches
        if let touches = event.allTouches {
            for touch in touches {
                if touch.phase == .began {
                    let location = touch.location(in: self)
                    let view = touch.view

                    DevSkin.shared.trackTouch(
                        type: "tap",
                        x: location.x,
                        y: location.y,
                        screenName: TouchCollector.shared.currentScreen,
                        elementId: view?.accessibilityIdentifier,
                        elementClass: view != nil ? String(describing: type(of: view!)) : nil
                    )
                }
            }
        }
    }
}

// MARK: - Gesture Recognizer Tracker
public class GestureTracker {
    public static func trackSwipe(_ recognizer: UISwipeGestureRecognizer, screenName: String) {
        var direction = "unknown"
        switch recognizer.direction {
        case .up: direction = "up"
        case .down: direction = "down"
        case .left: direction = "left"
        case .right: direction = "right"
        default: break
        }

        DevSkin.shared.trackGesture(
            type: "swipe",
            direction: direction,
            velocity: nil,
            screenName: screenName
        )
    }

    public static func trackPinch(_ recognizer: UIPinchGestureRecognizer, screenName: String) {
        if recognizer.state == .ended {
            DevSkin.shared.trackGesture(
                type: "pinch",
                direction: recognizer.scale > 1 ? "zoom_in" : "zoom_out",
                velocity: recognizer.velocity,
                screenName: screenName
            )
        }
    }

    public static func trackPan(_ recognizer: UIPanGestureRecognizer, screenName: String) {
        if recognizer.state == .ended {
            let velocity = recognizer.velocity(in: recognizer.view)
            DevSkin.shared.trackGesture(
                type: "pan",
                direction: nil,
                velocity: sqrt(velocity.x * velocity.x + velocity.y * velocity.y),
                screenName: screenName
            )
        }
    }

    public static func trackLongPress(_ recognizer: UILongPressGestureRecognizer, screenName: String) {
        if recognizer.state == .began {
            let location = recognizer.location(in: recognizer.view)
            DevSkin.shared.trackTouch(
                type: "long_press",
                x: location.x,
                y: location.y,
                screenName: screenName
            )
        }
    }
}
