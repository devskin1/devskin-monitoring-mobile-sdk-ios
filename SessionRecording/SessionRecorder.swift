import UIKit

// MARK: - Session Recording
public class SessionRecorder {
    public static let shared = SessionRecorder()

    private var isRecording = false
    private var sampleRate: Double = 1.0
    private var maskAllTextInputs = true
    private var maskedViews: Set<ObjectIdentifier> = []
    private var captureTimer: Timer?
    private var sessionId: String = ""
    private var frameIndex: Int = 0

    private let captureInterval: TimeInterval = 0.1 // 10 FPS
    private let serialQueue = DispatchQueue(label: "com.devskin.sessionrecording")

    private init() {}

    // MARK: - Configuration
    public func configure(
        sampleRate: Double = 1.0,
        maskAllTextInputs: Bool = true
    ) {
        self.sampleRate = sampleRate
        self.maskAllTextInputs = maskAllTextInputs
    }

    public func setSessionId(_ sessionId: String) {
        self.sessionId = sessionId
    }

    // MARK: - Start/Stop Recording
    public func startRecording() {
        guard !isRecording else { return }

        // Apply sampling
        guard Double.random(in: 0...1) <= sampleRate else { return }

        isRecording = true
        frameIndex = 0

        captureTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            self?.captureFrame()
        }
    }

    public func stopRecording() {
        guard isRecording else { return }

        isRecording = false
        captureTimer?.invalidate()
        captureTimer = nil
    }

    // MARK: - Mask Views
    public func maskView(_ view: UIView) {
        maskedViews.insert(ObjectIdentifier(view))
    }

    public func unmaskView(_ view: UIView) {
        maskedViews.remove(ObjectIdentifier(view))
    }

    // MARK: - Private Methods
    private func captureFrame() {
        guard isRecording else { return }

        serialQueue.async { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async {
                guard let window = self.getKeyWindow() else { return }

                // Create DOM-like snapshot
                let snapshot = self.createSnapshot(of: window)

                // Send to backend
                self.sendSnapshot(snapshot)
                self.frameIndex += 1
            }
        }
    }

    private func getKeyWindow() -> UIWindow? {
        if #available(iOS 15.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        } else {
            return UIApplication.shared.windows.first { $0.isKeyWindow }
        }
    }

    private func createSnapshot(of view: UIView) -> SnapshotNode {
        let frame = view.frame
        let type = getNodeType(view)

        var node = SnapshotNode(
            type: type,
            frame: FrameData(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.size.width,
                height: frame.size.height
            ),
            attributes: getAttributes(for: view),
            children: []
        )

        // Check if should mask
        let shouldMask = maskedViews.contains(ObjectIdentifier(view)) ||
                        (maskAllTextInputs && (view is UITextField || view is UITextView))

        if shouldMask {
            node.attributes["masked"] = true
            node.text = "[MASKED]"
        } else if let label = view as? UILabel {
            node.text = label.text
        } else if let button = view as? UIButton {
            node.text = button.titleLabel?.text
        }

        // Recursively capture children
        for subview in view.subviews where !subview.isHidden && subview.alpha > 0 {
            node.children.append(createSnapshot(of: subview))
        }

        return node
    }

    private func getNodeType(_ view: UIView) -> String {
        switch view {
        case is UILabel: return "label"
        case is UIButton: return "button"
        case is UITextField: return "text_field"
        case is UITextView: return "text_view"
        case is UIImageView: return "image"
        case is UITableView: return "table"
        case is UICollectionView: return "collection"
        case is UIScrollView: return "scroll"
        case is UIStackView: return "stack"
        case is UINavigationBar: return "nav_bar"
        case is UITabBar: return "tab_bar"
        case is UISwitch: return "switch"
        case is UISlider: return "slider"
        case is UIProgressView: return "progress"
        case is UIActivityIndicatorView: return "loader"
        default: return "view"
        }
    }

    private func getAttributes(for view: UIView) -> [String: Any] {
        var attrs: [String: Any] = [
            "hidden": view.isHidden,
            "alpha": view.alpha,
            "userInteractionEnabled": view.isUserInteractionEnabled
        ]

        if let backgroundColor = view.backgroundColor {
            attrs["backgroundColor"] = colorToHex(backgroundColor)
        }

        if let accessibilityIdentifier = view.accessibilityIdentifier {
            attrs["id"] = accessibilityIdentifier
        }

        if let accessibilityLabel = view.accessibilityLabel {
            attrs["accessibilityLabel"] = accessibilityLabel
        }

        // Type-specific attributes
        if let label = view as? UILabel {
            attrs["fontSize"] = label.font.pointSize
            attrs["textColor"] = colorToHex(label.textColor)
            attrs["textAlignment"] = textAlignmentString(label.textAlignment)
        } else if let button = view as? UIButton {
            attrs["enabled"] = button.isEnabled
            attrs["selected"] = button.isSelected
        } else if let textField = view as? UITextField {
            attrs["placeholder"] = textField.placeholder
            attrs["isSecure"] = textField.isSecureTextEntry
        } else if let imageView = view as? UIImageView {
            attrs["hasImage"] = imageView.image != nil
            attrs["contentMode"] = contentModeString(imageView.contentMode)
        } else if let scrollView = view as? UIScrollView {
            attrs["contentOffset"] = [
                "x": scrollView.contentOffset.x,
                "y": scrollView.contentOffset.y
            ]
            attrs["contentSize"] = [
                "width": scrollView.contentSize.width,
                "height": scrollView.contentSize.height
            ]
        }

        return attrs
    }

    private func colorToHex(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    private func textAlignmentString(_ alignment: NSTextAlignment) -> String {
        switch alignment {
        case .left: return "left"
        case .center: return "center"
        case .right: return "right"
        case .justified: return "justified"
        case .natural: return "natural"
        @unknown default: return "unknown"
        }
    }

    private func contentModeString(_ mode: UIView.ContentMode) -> String {
        switch mode {
        case .scaleToFill: return "scaleToFill"
        case .scaleAspectFit: return "aspectFit"
        case .scaleAspectFill: return "aspectFill"
        case .center: return "center"
        default: return "other"
        }
    }

    private func sendSnapshot(_ snapshot: SnapshotNode) {
        let data: [String: Any] = [
            "sessionId": sessionId,
            "frameIndex": frameIndex,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "snapshot": snapshot.toDictionary()
        ]

        // Send to backend (we'll use a dedicated endpoint)
        // MobileTransport.shared.sendSessionRecordingFrame(data)
    }
}

// MARK: - Snapshot Data Structures
struct SnapshotNode {
    let type: String
    let frame: FrameData
    var attributes: [String: Any]
    var children: [SnapshotNode]
    var text: String?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type,
            "frame": frame.toDictionary(),
            "attributes": attributes,
            "children": children.map { $0.toDictionary() }
        ]
        if let text = text { dict["text"] = text }
        return dict
    }
}

struct FrameData {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    func toDictionary() -> [String: Any] {
        return ["x": x, "y": y, "width": width, "height": height]
    }
}

// MARK: - View Extension for Masking
public extension UIView {
    func maskForRecording() {
        SessionRecorder.shared.maskView(self)
    }

    func unmaskForRecording() {
        SessionRecorder.shared.unmaskView(self)
    }
}

// MARK: - Sensitive Fields Auto-Detection
public class SensitiveFieldDetector {
    private static let sensitivePatterns = [
        "password", "senha", "pwd", "pass",
        "credit", "card", "cartao", "cvv", "cvc",
        "ssn", "cpf", "rg", "social",
        "secret", "token", "key"
    ]

    public static func isSensitive(view: UIView) -> Bool {
        // Check accessibility identifier
        if let identifier = view.accessibilityIdentifier?.lowercased() {
            for pattern in sensitivePatterns {
                if identifier.contains(pattern) {
                    return true
                }
            }
        }

        // Check if it's a secure text field
        if let textField = view as? UITextField {
            return textField.isSecureTextEntry
        }

        return false
    }

    public static func autoMaskSensitiveViews(in view: UIView) {
        if isSensitive(view: view) {
            SessionRecorder.shared.maskView(view)
        }

        for subview in view.subviews {
            autoMaskSensitiveViews(in: subview)
        }
    }
}
