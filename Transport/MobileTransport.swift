import Foundation

// MARK: - Mobile Transport Layer
public class MobileTransport {
    public static let shared = MobileTransport()

    private var config: DevSkinConfig?
    private var sessionId: String?
    private var queue: [QueuedItem] = []
    private var offlineQueue: [QueuedItem] = []
    private var flushTimer: Timer?

    private let maxQueueSize = 30
    private let flushIntervalMs: TimeInterval = 5.0
    private let maxRetries = 3

    private var isOnline = true
    private let serialQueue = DispatchQueue(label: "com.devskin.transport")

    private init() {}

    public func configure(config: DevSkinConfig) {
        self.config = config
        startPeriodicFlush()
        setupNetworkMonitor()
    }

    public func setSessionId(_ sessionId: String) {
        self.sessionId = sessionId
    }

    // MARK: - Session Endpoints
    public func startSession(_ session: SessionData) {
        sendToBackend(endpoint: "/v1/rum/sessions", data: session.toDictionary())
    }

    public func updateSession(sessionId: String, data: [String: Any]) {
        sendToBackend(endpoint: "/v1/rum/sessions/\(sessionId)", data: data, method: "PUT")
    }

    // MARK: - Event Endpoints
    public func sendEvent(_ event: EventData) {
        enqueue(type: .event, data: event.toDictionary())
    }

    // MARK: - Error Endpoints
    public func sendError(_ error: CrashData) {
        // Errors sent immediately
        sendToBackend(endpoint: "/v1/errors/errors", data: error.toDictionary()) { [weak self] success in
            if !success {
                self?.enqueue(type: .error, data: error.toDictionary())
            }
        }
    }

    // MARK: - Network Request
    public func sendNetworkRequest(_ request: NetworkRequestData) {
        enqueue(type: .network, data: request.toDictionary())
    }

    // MARK: - Performance Metric
    public func sendPerformanceMetric(_ metric: PerformanceMetricData) {
        enqueue(type: .performance, data: metric.toDictionary())
    }

    // MARK: - Heatmap/Touch Data
    public func sendTouchData(_ touch: TouchData) {
        var data = touch.toDictionary()
        data["type"] = touch.type.rawValue
        enqueue(type: .heatmap, data: data)
    }

    public func sendScrollData(_ scroll: ScrollData) {
        var data = scroll.toDictionary()
        data["type"] = "scroll"
        enqueue(type: .heatmap, data: data)
    }

    // MARK: - Session Recording
    public func sendRecordingEvents(_ events: [[String: Any]]) {
        guard !events.isEmpty else { return }
        let payload: [String: Any] = [
            "session_id": sessionId ?? "",
            "events": events,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        sendToBackend(endpoint: "/v1/rum/recordings", data: payload)
    }

    // MARK: - Screen View
    public func sendScreenView(_ screenView: ScreenViewData) {
        enqueue(type: .screen, data: screenView.toDictionary())
    }

    // MARK: - Manual Flush
    public func flush() {
        serialQueue.async { [weak self] in
            self?.performFlush()
        }
    }

    public func destroy() {
        flushTimer?.invalidate()
        flushTimer = nil
        flush()
    }

    // MARK: - Private Methods
    private func enqueue(type: QueueType, data: [String: Any]) {
        serialQueue.async { [weak self] in
            guard let self = self else { return }

            var enrichedData = data
            enrichedData["applicationId"] = self.config?.appId
            enrichedData["sessionId"] = self.sessionId ?? data["sessionId"]
            enrichedData["platform"] = "mobile"

            let item = QueuedItem(type: type, data: enrichedData, timestamp: Date(), retryCount: 0)

            if self.isOnline {
                self.queue.append(item)
                if self.queue.count >= self.maxQueueSize {
                    self.performFlush()
                }
            } else {
                self.offlineQueue.append(item)
            }
        }
    }

    private func performFlush() {
        guard !queue.isEmpty, let config = config else { return }

        let items = queue
        queue.removeAll()

        // Group by type
        var grouped: [QueueType: [[String: Any]]] = [:]
        for item in items {
            if grouped[item.type] == nil {
                grouped[item.type] = []
            }
            grouped[item.type]?.append(item.data)
        }

        // Send each type
        for (type, dataArray) in grouped {
            let endpoint = getEndpoint(for: type)

            if type == .event && dataArray.count > 1 {
                sendToBackend(endpoint: "/v1/rum/events/batch", data: ["events": dataArray])
            } else if type == .heatmap {
                sendToBackend(endpoint: endpoint, data: [
                    "heatmaps": dataArray,
                    "apiKey": config.apiKey,
                    "appId": config.appId
                ])
            } else {
                for data in dataArray {
                    sendToBackend(endpoint: endpoint, data: data)
                }
            }
        }

        log("Flushed \(items.count) items")
    }

    private func startPeriodicFlush() {
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushIntervalMs, repeats: true) { [weak self] _ in
            self?.flush()
        }
    }

    private func setupNetworkMonitor() {
        // Use NWPathMonitor for iOS 12+
        if #available(iOS 12.0, *) {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                let wasOffline = !(self?.isOnline ?? true)
                self?.isOnline = path.status == .satisfied

                // If we came back online, flush offline queue
                if wasOffline && self?.isOnline == true {
                    self?.flushOfflineQueue()
                }
            }
            monitor.start(queue: serialQueue)
        }
    }

    private func flushOfflineQueue() {
        serialQueue.async { [weak self] in
            guard let self = self else { return }
            self.queue.append(contentsOf: self.offlineQueue)
            self.offlineQueue.removeAll()
            self.performFlush()
        }
    }

    private func getEndpoint(for type: QueueType) -> String {
        switch type {
        case .event: return "/v1/rum/events"
        case .error: return "/v1/errors/errors"
        case .network: return "/v1/rum/network-requests"
        case .performance: return "/v1/rum/web-vitals"
        case .heatmap: return "/v1/sdk/heatmap"
        case .screen: return "/v1/rum/page-views"
        }
    }

    private func sendToBackend(endpoint: String, data: [String: Any], method: String = "POST", completion: ((Bool) -> Void)? = nil) {
        guard let config = config else {
            completion?(false)
            return
        }

        let urlString = "\(config.apiUrl)\(endpoint)"
        guard let url = URL(string: urlString) else {
            completion?(false)
            return
        }

        var payload = data
        payload["apiKey"] = config.apiKey
        payload["applicationId"] = config.appId

        // Apply beforeSend hook
        if let beforeSend = config.beforeSend {
            guard let processed = beforeSend(payload) else {
                completion?(true) // Hook returned nil, skip sending
                return
            }
            payload = processed
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(config.appId, forHTTPHeaderField: "X-App-Id")
        request.setValue("mobile", forHTTPHeaderField: "X-Platform")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion?(false)
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            let httpResponse = response as? HTTPURLResponse
            let success = error == nil && (httpResponse?.statusCode ?? 500) < 400

            if self?.config?.debug == true {
                self?.log("Sent to \(endpoint): \(httpResponse?.statusCode ?? 0)")
            }

            completion?(success)
        }.resume()
    }

    private func log(_ message: String) {
        if config?.debug == true {
            print("[DevSkin Mobile] \(message)")
        }
    }
}

// MARK: - Supporting Types
enum QueueType {
    case event, error, network, performance, heatmap, screen
}

struct QueuedItem {
    let type: QueueType
    let data: [String: Any]
    let timestamp: Date
    var retryCount: Int
}

// MARK: - Data Structures
public struct SessionData {
    let sessionId: String
    let userId: String?
    let anonymousId: String
    let startedAt: Date
    var endedAt: Date?
    let platform: String
    let device: DeviceData?
    let app: AppData?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "sessionId": sessionId,
            "anonymousId": anonymousId,
            "startedAt": ISO8601DateFormatter().string(from: startedAt),
            "platform": platform
        ]
        if let userId = userId { dict["userId"] = userId }
        if let device = device { dict["device"] = device.toDictionary() }
        if let app = app { dict["app"] = app.toDictionary() }
        return dict
    }
}

public struct DeviceData {
    let type: DeviceType
    let manufacturer: String?
    let model: String?
    let os: OSInfo
    let screen: ScreenInfo
    let memory: MemoryInfo?
    let storage: StorageInfo?
    let battery: BatteryInfo?
    let network: NetworkInfo?
    let isEmulator: Bool
    let isJailbroken: Bool?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type.rawValue,
            "os": os.toDictionary(),
            "screen": screen.toDictionary(),
            "isEmulator": isEmulator
        ]
        if let manufacturer = manufacturer { dict["manufacturer"] = manufacturer }
        if let model = model { dict["model"] = model }
        if let memory = memory { dict["memory"] = memory.toDictionary() }
        if let storage = storage { dict["storage"] = storage.toDictionary() }
        if let battery = battery { dict["battery"] = battery.toDictionary() }
        if let network = network { dict["network"] = network.toDictionary() }
        if let isJailbroken = isJailbroken { dict["isJailbroken"] = isJailbroken }
        return dict
    }
}

public enum DeviceType: String {
    case phone, tablet
}

public struct OSInfo {
    let name: String
    let version: String

    func toDictionary() -> [String: Any] {
        return ["name": name, "version": version]
    }
}

public struct ScreenInfo {
    let width: Int
    let height: Int
    let density: Float
    var orientation: String

    func toDictionary() -> [String: Any] {
        return ["width": width, "height": height, "density": density, "orientation": orientation]
    }
}

public struct MemoryInfo {
    let total: UInt64
    let available: UInt64

    func toDictionary() -> [String: Any] {
        return ["total": total, "available": available]
    }
}

public struct StorageInfo {
    let total: UInt64
    let available: UInt64

    func toDictionary() -> [String: Any] {
        return ["total": total, "available": available]
    }
}

public struct BatteryInfo {
    let level: Float
    let charging: Bool

    func toDictionary() -> [String: Any] {
        return ["level": level, "charging": charging]
    }
}

public struct NetworkInfo {
    let type: String
    let effectiveType: String?
    let carrier: String?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["type": type]
        if let effectiveType = effectiveType { dict["effectiveType"] = effectiveType }
        if let carrier = carrier { dict["carrier"] = carrier }
        return dict
    }
}

public struct AppData {
    let name: String
    let version: String
    let build: String
    let bundleId: String
    let installSource: String?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "version": version,
            "build": build,
            "bundleId": bundleId
        ]
        if let installSource = installSource { dict["installSource"] = installSource }
        return dict
    }
}

public struct EventData {
    let eventName: String
    let eventType: String
    let timestamp: Date
    let sessionId: String
    let userId: String?
    let anonymousId: String?
    let properties: [String: Any]?
    let screenName: String?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "eventName": eventName,
            "eventType": eventType,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "sessionId": sessionId
        ]
        if let userId = userId { dict["userId"] = userId }
        if let anonymousId = anonymousId { dict["anonymousId"] = anonymousId }
        if let properties = properties { dict["properties"] = properties }
        if let screenName = screenName { dict["screenName"] = screenName }
        return dict
    }
}

public struct CrashData {
    let message: String
    let stack: String?
    let type: CrashType
    let timestamp: Date
    let sessionId: String
    let userId: String?
    let screenName: String?
    let breadcrumbs: [Breadcrumb]?
    let context: [String: Any]?
    let device: DeviceData?
    let app: AppData?
    let isFatal: Bool
    let signal: String?
    let nativeStack: [NativeStackFrame]?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "message": message,
            "type": type.rawValue,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "sessionId": sessionId,
            "isFatal": isFatal
        ]
        if let stack = stack { dict["stack"] = stack }
        if let userId = userId { dict["userId"] = userId }
        if let screenName = screenName { dict["screenName"] = screenName }
        if let breadcrumbs = breadcrumbs { dict["breadcrumbs"] = breadcrumbs.map { $0.toDictionary() } }
        if let context = context { dict["context"] = context }
        if let device = device { dict["device"] = device.toDictionary() }
        if let app = app { dict["app"] = app.toDictionary() }
        if let signal = signal { dict["signal"] = signal }
        if let nativeStack = nativeStack { dict["nativeStack"] = nativeStack.map { $0.toDictionary() } }
        return dict
    }
}

public enum CrashType: String {
    case javascript, native, anr, oom
}

public struct Breadcrumb {
    let category: String
    let message: String
    let level: BreadcrumbLevel
    let timestamp: Date
    let data: [String: Any]?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "category": category,
            "message": message,
            "level": level.rawValue,
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
        if let data = data { dict["data"] = data }
        return dict
    }
}

public enum BreadcrumbLevel: String {
    case debug, info, warning, error, fatal
}

public struct NativeStackFrame {
    let file: String?
    let function: String?
    let line: Int?
    let column: Int?
    let address: String?
    let symbol: String?
    let image: String?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let file = file { dict["file"] = file }
        if let function = function { dict["function"] = function }
        if let line = line { dict["line"] = line }
        if let column = column { dict["column"] = column }
        if let address = address { dict["address"] = address }
        if let symbol = symbol { dict["symbol"] = symbol }
        if let image = image { dict["image"] = image }
        return dict
    }
}

public struct NetworkRequestData {
    let sessionId: String
    let url: String
    let method: String
    let statusCode: Int?
    let durationMs: Int
    let requestSize: Int?
    let responseSize: Int?
    let errorMessage: String?
    let timestamp: Date

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "sessionId": sessionId,
            "url": url,
            "method": method,
            "durationMs": durationMs,
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
        if let statusCode = statusCode { dict["statusCode"] = statusCode }
        if let requestSize = requestSize { dict["requestSize"] = requestSize }
        if let responseSize = responseSize { dict["responseSize"] = responseSize }
        if let errorMessage = errorMessage { dict["errorMessage"] = errorMessage }
        return dict
    }
}

public struct PerformanceMetricData {
    let sessionId: String
    let metricName: String
    let value: Double
    let screenName: String?
    let timestamp: Date
    let context: [String: Any]?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "sessionId": sessionId,
            "metricName": metricName,
            "value": value,
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
        if let screenName = screenName { dict["screenName"] = screenName }
        if let context = context { dict["context"] = context }
        return dict
    }
}

public struct TouchData {
    let type: TouchType
    let x: CGFloat
    let y: CGFloat
    let relativeX: CGFloat
    let relativeY: CGFloat
    let screenName: String
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let timestamp: Date
    let direction: String?
    let velocity: CGFloat?
    let duration: TimeInterval?
    let force: CGFloat?
    let elementType: String?
    let elementId: String?
    let elementLabel: String?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "x": x,
            "y": y,
            "relativeX": relativeX,
            "relativeY": relativeY,
            "screenName": screenName,
            "screenWidth": screenWidth,
            "screenHeight": screenHeight,
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
        if let direction = direction { dict["direction"] = direction }
        if let velocity = velocity { dict["velocity"] = velocity }
        if let duration = duration { dict["duration"] = duration }
        if let force = force { dict["force"] = force }
        if let elementType = elementType { dict["elementType"] = elementType }
        if let elementId = elementId { dict["elementId"] = elementId }
        if let elementLabel = elementLabel { dict["elementLabel"] = elementLabel }
        return dict
    }
}

public enum TouchType: String {
    case tap, longPress, swipe, pinch, scroll
}

public struct ScrollData {
    let screenName: String
    let scrollDepth: Int
    let maxScrollDepth: Int
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
    let direction: String
    let timestamp: Date

    func toDictionary() -> [String: Any] {
        return [
            "screenName": screenName,
            "scrollDepth": scrollDepth,
            "maxScrollDepth": maxScrollDepth,
            "contentHeight": contentHeight,
            "viewportHeight": viewportHeight,
            "direction": direction,
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
    }
}

public struct ScreenViewData {
    let sessionId: String
    let screenName: String
    let screenClass: String?
    let timestamp: Date
    let previousScreen: String?
    let renderTime: Int?
    let properties: [String: Any]?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "sessionId": sessionId,
            "screenName": screenName,
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
        if let screenClass = screenClass { dict["screenClass"] = screenClass }
        if let previousScreen = previousScreen { dict["previousScreen"] = previousScreen }
        if let renderTime = renderTime { dict["renderTime"] = renderTime }
        if let properties = properties { dict["properties"] = properties }
        return dict
    }
}

// MARK: - Import Network for NWPathMonitor
import Network
