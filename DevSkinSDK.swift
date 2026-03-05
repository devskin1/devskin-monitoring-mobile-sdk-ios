import Foundation
import UIKit
import SystemConfiguration

// MARK: - Callbacks
public typealias BeforeSendCallback = ([String: Any]) -> [String: Any]?
public typealias OnErrorCallback = (Error) -> Void

// MARK: - Configuration
public struct DevSkinConfig {
    public let apiKey: String
    public let appId: String
    public let apiUrl: String
    public var debug: Bool
    public var sessionRecording: SessionRecordingConfig
    public var performance: PerformanceConfig
    public var network: NetworkConfig
    public var heatmap: HeatmapConfig
    public var privacy: PrivacyConfig
    public var beforeSend: BeforeSendCallback?
    public var onError: OnErrorCallback?

    public init(
        apiKey: String,
        appId: String,
        apiUrl: String = "https://api-monitoring.devskin.com",
        debug: Bool = false,
        sessionRecording: SessionRecordingConfig = SessionRecordingConfig(),
        performance: PerformanceConfig = PerformanceConfig(),
        network: NetworkConfig = NetworkConfig(),
        heatmap: HeatmapConfig = HeatmapConfig(),
        privacy: PrivacyConfig = PrivacyConfig(),
        beforeSend: BeforeSendCallback? = nil,
        onError: OnErrorCallback? = nil
    ) {
        self.apiKey = apiKey
        self.appId = appId
        self.apiUrl = apiUrl
        self.debug = debug
        self.sessionRecording = sessionRecording
        self.performance = performance
        self.network = network
        self.heatmap = heatmap
        self.privacy = privacy
        self.beforeSend = beforeSend
        self.onError = onError
    }
}

public struct SessionRecordingConfig {
    public var enabled: Bool = true
    public var sampleRate: Double = 1.0
    public var maskAllTextInputs: Bool = true
}

public struct PerformanceConfig {
    public var enabled: Bool = true
    public var trackAppLaunch: Bool = true
    public var trackScreenRender: Bool = true
    public var trackNetworkLatency: Bool = true
}

public struct NetworkConfig {
    public var enabled: Bool = true
    public var captureRequestBody: Bool = false
    public var captureResponseBody: Bool = false
    public var ignoredUrls: [String] = []
}

public struct HeatmapConfig {
    public var enabled: Bool = true
    public var trackTouches: Bool = true
    public var trackScrolls: Bool = true
    public var trackGestures: Bool = true
}

public struct PrivacyConfig {
    public var maskSensitiveData: Bool = true
    public var respectDoNotTrack: Bool = true
}

// MARK: - Event Types
public enum EventType: String, Codable {
    case track
    case screen
    case crash
    case error
    case performance
    case network
    case touch
    case gesture
    case session
}

public struct DevSkinEvent: Codable {
    public let id: String
    public let type: EventType
    public let name: String
    public let timestamp: Date
    public let sessionId: String
    public let properties: [String: AnyCodable]?
    public let context: EventContext
}

public struct EventContext: Codable {
    public let device: DeviceInfo
    public let app: AppInfo
    public let screen: ScreenInfo?
    public let location: LocationInfo?
}

public struct DeviceInfo: Codable {
    public let model: String
    public let manufacturer: String
    public let osName: String
    public let osVersion: String
    public let screenWidth: Int
    public let screenHeight: Int
    public let screenDensity: Double
    public let locale: String
    public let timezone: String
    public let isEmulator: Bool
    public let batteryLevel: Double?
    public let isCharging: Bool?
    public let networkType: String?
    public let carrier: String?
    // New fields for parity with React Native
    public let deviceType: String // "phone" or "tablet"
    public let isJailbroken: Bool
    public let orientation: String // "portrait" or "landscape"
    public let totalMemory: Int?
    public let availableMemory: Int?
    public let totalStorage: Int?
    public let availableStorage: Int?
}

public struct AppInfo: Codable {
    public let name: String
    public let version: String
    public let build: String
    public let bundleId: String
}

public struct ScreenInfo: Codable {
    public let name: String
    public let className: String?
}

public struct LocationInfo: Codable {
    public let country: String?
    public let region: String?
    public let city: String?
    public let latitude: Double?
    public let longitude: Double?
}

// MARK: - User
public struct DevSkinUser: Codable {
    public let id: String
    public var email: String?
    public var name: String?
    public var traits: [String: AnyCodable]?

    public init(id: String, email: String? = nil, name: String? = nil, traits: [String: AnyCodable]? = nil) {
        self.id = id
        self.email = email
        self.name = name
        self.traits = traits
    }
}

// MARK: - AnyCodable Helper
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - Breadcrumb
public struct Breadcrumb {
    public let category: String
    public let message: String
    public let level: BreadcrumbLevel
    public let timestamp: Date
    public let data: [String: Any]?

    public init(category: String, message: String, level: BreadcrumbLevel = .info, data: [String: Any]? = nil) {
        self.category = category
        self.message = message
        self.level = level
        self.timestamp = Date()
        self.data = data
    }
}

public enum BreadcrumbLevel: String {
    case debug, info, warning, error, fatal
}

// MARK: - Main SDK Class
public class DevSkin {
    public static let shared = DevSkin()

    private var config: DevSkinConfig?
    private var sessionId: String = ""
    private var currentUser: DevSkinUser?
    private var isInitialized = false
    private var eventQueue: [DevSkinEvent] = []
    private var deviceInfo: DeviceInfo?
    private var appInfo: AppInfo?
    private var currentScreen: String = ""

    // Breadcrumbs
    private var breadcrumbs: [Breadcrumb] = []
    private let maxBreadcrumbs = 50
    private let breadcrumbLock = NSLock()

    // Offline queue
    private var offlineQueue: [[String: Any]] = []
    private var isOnline = true

    private let eventQueueLock = NSLock()
    private var flushTimer: Timer?
    private let flushInterval: TimeInterval = 30
    private let maxBatchSize = 100

    private init() {}

    // MARK: - Initialization
    public func initialize(config: DevSkinConfig) {
        guard !isInitialized else {
            log("SDK already initialized")
            return
        }

        self.config = config
        self.sessionId = UUID().uuidString
        self.deviceInfo = collectDeviceInfo()
        self.appInfo = collectAppInfo()
        self.isInitialized = true

        setupFlushTimer()
        setupLifecycleObservers()
        setupCrashHandler()

        // Configure MobileTransport
        MobileTransport.shared.configure(config: config)
        MobileTransport.shared.setSessionId(sessionId)

        // Setup session recording
        if config.sessionRecording.enabled {
            setupSessionRecording()
        }

        // Track session start
        trackSessionStart()

        log("DevSkin SDK initialized with appId: \(config.appId)")
    }

    // MARK: - Public Methods
    public func track(_ eventName: String, properties: [String: Any]? = nil) {
        guard isInitialized else {
            log("SDK not initialized. Call initialize() first.")
            return
        }

        let event = createEvent(
            type: .track,
            name: eventName,
            properties: properties?.mapValues { AnyCodable($0) }
        )

        enqueueEvent(event)
    }

    public func screen(_ screenName: String, properties: [String: Any]? = nil) {
        guard isInitialized else { return }

        let previousScreen = currentScreen
        currentScreen = screenName

        // Notify session recorder of screen change
        if config?.sessionRecording.enabled == true {
            SessionRecorder.shared.setCurrentScreen(screenName)
        }

        var props = properties ?? [:]
        props["screen_name"] = screenName
        if !previousScreen.isEmpty {
            props["previous_screen"] = previousScreen
        }

        // Add navigation breadcrumb
        if !previousScreen.isEmpty {
            addBreadcrumb(
                category: "navigation",
                message: "Navigated from \(previousScreen) to \(screenName)",
                level: .info,
                data: ["from": previousScreen, "to": screenName]
            )
        }

        let event = createEvent(
            type: .screen,
            name: "screen_view",
            properties: props.mapValues { AnyCodable($0) },
            screenInfo: ScreenInfo(name: screenName, className: nil)
        )

        enqueueEvent(event)
    }

    public func identify(user: DevSkinUser) {
        guard isInitialized else { return }

        self.currentUser = user

        var props: [String: Any] = ["user_id": user.id]
        if let email = user.email { props["email"] = email }
        if let name = user.name { props["name"] = name }
        if let traits = user.traits {
            for (key, value) in traits {
                props[key] = value.value
            }
        }

        track("identify", properties: props)
        log("User identified: \(user.id)")
    }

    public func clearUser() {
        currentUser = nil
        sessionId = UUID().uuidString
        log("User cleared, new session started")
    }

    public func trackError(_ error: Error, context: [String: Any]? = nil) {
        guard isInitialized else { return }

        var props: [String: Any] = [
            "error_message": error.localizedDescription,
            "error_type": String(describing: type(of: error))
        ]

        if let nsError = error as NSError? {
            props["error_domain"] = nsError.domain
            props["error_code"] = nsError.code
        }

        if let ctx = context {
            for (key, value) in ctx {
                props[key] = value
            }
        }

        let event = createEvent(
            type: .error,
            name: "error",
            properties: props.mapValues { AnyCodable($0) }
        )

        enqueueEvent(event)
    }

    public func trackPerformance(metric: String, value: Double, unit: String = "ms", context: [String: Any]? = nil) {
        guard isInitialized, config?.performance.enabled == true else { return }

        var props: [String: Any] = [
            "metric": metric,
            "value": value,
            "unit": unit
        ]

        if let ctx = context {
            for (key, value) in ctx {
                props[key] = value
            }
        }

        let event = createEvent(
            type: .performance,
            name: "performance_metric",
            properties: props.mapValues { AnyCodable($0) }
        )

        enqueueEvent(event)
    }

    public func trackNetworkRequest(
        url: String,
        method: String,
        statusCode: Int?,
        duration: TimeInterval,
        requestSize: Int?,
        responseSize: Int?,
        error: Error? = nil
    ) {
        guard isInitialized, config?.network.enabled == true else { return }

        // Check if URL should be ignored
        if let ignoredUrls = config?.network.ignoredUrls {
            for pattern in ignoredUrls {
                if url.contains(pattern) { return }
            }
        }

        var props: [String: Any] = [
            "url": url,
            "method": method,
            "duration_ms": duration * 1000
        ]

        if let code = statusCode { props["status_code"] = code }
        if let reqSize = requestSize { props["request_size"] = reqSize }
        if let resSize = responseSize { props["response_size"] = resSize }
        if let err = error { props["error"] = err.localizedDescription }

        let event = createEvent(
            type: .network,
            name: "network_request",
            properties: props.mapValues { AnyCodable($0) }
        )

        enqueueEvent(event)
    }

    public func trackTouch(
        type: String,
        x: CGFloat,
        y: CGFloat,
        screenName: String,
        elementId: String? = nil,
        elementClass: String? = nil,
        force: CGFloat? = nil,
        duration: TimeInterval? = nil,
        direction: String? = nil,
        velocity: CGFloat? = nil
    ) {
        guard isInitialized, config?.heatmap.trackTouches == true else { return }

        // Also record touch for session replay
        if config?.sessionRecording.enabled == true {
            SessionRecorder.shared.recordTouch(type: type, x: x, y: y, screenName: screenName)
        }

        let screen = UIScreen.main.bounds
        let screenWidth = screen.width
        let screenHeight = screen.height

        var props: [String: Any] = [
            "touch_type": type,
            "x": x,
            "y": y,
            "relativeX": screenWidth > 0 ? x / screenWidth : 0,
            "relativeY": screenHeight > 0 ? y / screenHeight : 0,
            "screen_name": screenName,
            "screenWidth": screenWidth,
            "screenHeight": screenHeight
        ]

        if let id = elementId { props["element_id"] = id }
        if let cls = elementClass { props["element_class"] = cls }
        if let f = force { props["force"] = f }
        if let d = duration { props["duration"] = d * 1000 } // Convert to ms
        if let dir = direction { props["direction"] = dir }
        if let vel = velocity { props["velocity"] = vel }

        let event = createEvent(
            type: .touch,
            name: "touch",
            properties: props.mapValues { AnyCodable($0) },
            screenInfo: ScreenInfo(name: screenName, className: nil)
        )

        enqueueEvent(event)
    }

    public func trackGesture(
        type: String,
        direction: String? = nil,
        velocity: CGFloat? = nil,
        screenName: String
    ) {
        guard isInitialized, config?.heatmap.trackGestures == true else { return }

        var props: [String: Any] = [
            "gesture_type": type,
            "screen_name": screenName
        ]

        if let dir = direction { props["direction"] = dir }
        if let vel = velocity { props["velocity"] = vel }

        let event = createEvent(
            type: .gesture,
            name: "gesture",
            properties: props.mapValues { AnyCodable($0) },
            screenInfo: ScreenInfo(name: screenName, className: nil)
        )

        enqueueEvent(event)
    }

    public func flush() {
        sendEvents()
    }

    // MARK: - Breadcrumbs
    public func addBreadcrumb(category: String, message: String, level: BreadcrumbLevel = .info, data: [String: Any]? = nil) {
        breadcrumbLock.lock()
        defer { breadcrumbLock.unlock() }

        let breadcrumb = Breadcrumb(category: category, message: message, level: level, data: data)
        breadcrumbs.append(breadcrumb)

        // Keep only last N breadcrumbs
        while breadcrumbs.count > maxBreadcrumbs {
            breadcrumbs.removeFirst()
        }
    }

    public func getBreadcrumbs() -> [Breadcrumb] {
        breadcrumbLock.lock()
        defer { breadcrumbLock.unlock() }
        return breadcrumbs
    }

    public func clearBreadcrumbs() {
        breadcrumbLock.lock()
        defer { breadcrumbLock.unlock() }
        breadcrumbs.removeAll()
    }

    // MARK: - Scroll Tracking
    public func trackScroll(scrollY: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat, screenName: String? = nil) {
        guard isInitialized, config?.heatmap.trackScrolls == true else { return }

        let maxScrollY = contentHeight - viewportHeight
        guard maxScrollY > 0 else { return }

        let scrollDepth = min(100, max(0, Int((scrollY / maxScrollY) * 100)))

        // Also record scroll for session replay
        if config?.sessionRecording.enabled == true {
            SessionRecorder.shared.recordScroll(scrollY: scrollY, scrollDepth: scrollDepth, screenName: screenName ?? currentScreen)
        }

        var props: [String: Any] = [
            "scrollDepth": scrollDepth,
            "maxScrollDepth": scrollDepth,
            "contentHeight": contentHeight,
            "viewportHeight": viewportHeight,
            "direction": "down",
            "screen_name": screenName ?? currentScreen
        ]

        let event = createEvent(
            type: .gesture,
            name: "scroll",
            properties: props.mapValues { AnyCodable($0) },
            screenInfo: ScreenInfo(name: screenName ?? currentScreen, className: nil)
        )

        enqueueEvent(event)
    }

    // MARK: - Private Methods
    private func createEvent(
        type: EventType,
        name: String,
        properties: [String: AnyCodable]? = nil,
        screenInfo: ScreenInfo? = nil
    ) -> DevSkinEvent {
        let context = EventContext(
            device: deviceInfo ?? collectDeviceInfo(),
            app: appInfo ?? collectAppInfo(),
            screen: screenInfo,
            location: nil
        )

        return DevSkinEvent(
            id: UUID().uuidString,
            type: type,
            name: name,
            timestamp: Date(),
            sessionId: sessionId,
            properties: properties,
            context: context
        )
    }

    private func enqueueEvent(_ event: DevSkinEvent) {
        eventQueueLock.lock()
        defer { eventQueueLock.unlock() }

        eventQueue.append(event)

        if eventQueue.count >= maxBatchSize {
            sendEvents()
        }
    }

    private func sendEvents() {
        eventQueueLock.lock()
        let eventsToSend = eventQueue
        eventQueue = []
        eventQueueLock.unlock()

        guard !eventsToSend.isEmpty, let config = config else { return }

        let endpoint = "\(config.apiUrl)/v1/rum/events/batch"

        guard let url = URL(string: endpoint) else {
            log("Invalid API URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(config.appId, forHTTPHeaderField: "X-App-Id")
        request.setValue("mobile", forHTTPHeaderField: "X-Platform")

        var payload: [String: Any] = [
            "events": eventsToSend.map { eventToDict($0) },
            "apiKey": config.apiKey,
            "applicationId": config.appId
        ]

        // Apply beforeSend hook
        if let beforeSend = config.beforeSend {
            guard let processedPayload = beforeSend(payload) else {
                log("beforeSend returned nil, skipping send")
                return
            }
            payload = processedPayload
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            log("Failed to serialize events: \(error)")
            // Call onError callback
            config.onError?(error)
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                self?.log("Failed to send events: \(error)")
                // Call onError callback
                self?.config?.onError?(error)
                // Re-queue events for retry
                self?.eventQueueLock.lock()
                eventsToSend.forEach { self?.eventQueue.append($0) }
                self?.eventQueueLock.unlock()
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                self?.log("Events sent: \(eventsToSend.count), status: \(httpResponse.statusCode)")
            }
        }.resume()
    }

    private func eventToDict(_ event: DevSkinEvent) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var dict: [String: Any] = [
            "applicationId": config!.appId,
            "eventName": event.name,
            "eventType": event.type.rawValue,
            "timestamp": formatter.string(from: event.timestamp),
            "sessionId": event.sessionId
        ]

        if let userId = currentUser?.id {
            dict["userId"] = userId
        }

        if let properties = event.properties {
            var propsDict: [String: Any] = [:]
            for (key, value) in properties {
                propsDict[key] = value.value
            }
            dict["properties"] = propsDict
        }

        if let screenInfo = event.context.screen {
            dict["pageUrl"] = "mobile://\(screenInfo.name)"
            dict["pageTitle"] = screenInfo.name
        }

        return dict
    }

    private func collectDeviceInfo() -> DeviceInfo {
        let device = UIDevice.current
        let screen = UIScreen.main

        return DeviceInfo(
            model: getDeviceModel(),
            manufacturer: "Apple",
            osName: "iOS",
            osVersion: device.systemVersion,
            screenWidth: Int(screen.bounds.width * screen.scale),
            screenHeight: Int(screen.bounds.height * screen.scale),
            screenDensity: Double(screen.scale),
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier,
            isEmulator: isSimulator(),
            batteryLevel: getBatteryLevel(),
            isCharging: device.batteryState == .charging || device.batteryState == .full,
            networkType: getNetworkType(),
            carrier: getCarrier(),
            deviceType: getDeviceType(),
            isJailbroken: checkJailbroken(),
            orientation: getOrientation(),
            totalMemory: getTotalMemory(),
            availableMemory: getAvailableMemory(),
            totalStorage: getTotalStorage(),
            availableStorage: getAvailableStorage()
        )
    }

    private func getDeviceType() -> String {
        return UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone"
    }

    private func checkJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        // Check for common jailbreak files
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/usr/bin/ssh",
            "/private/var/lib/cydia",
            "/private/var/stash"
        ]

        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }

        // Check if app can write outside sandbox
        let testPath = "/private/jailbreak_test.txt"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {
            return false
        }
        #endif
    }

    private func getOrientation() -> String {
        let orientation = UIDevice.current.orientation
        switch orientation {
        case .landscapeLeft, .landscapeRight:
            return "landscape"
        default:
            return "portrait"
        }
    }

    private func getTotalMemory() -> Int? {
        return Int(ProcessInfo.processInfo.physicalMemory / 1024 / 1024) // MB
    }

    private func getAvailableMemory() -> Int? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let used = Int(info.resident_size / 1024 / 1024) // MB
        if let total = getTotalMemory() {
            return total - used
        }
        return nil
    }

    private func getTotalStorage() -> Int? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let space = attrs[.systemSize] as? Int64 else {
            return nil
        }
        return Int(space / 1024 / 1024) // MB
    }

    private func getAvailableStorage() -> Int? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let space = attrs[.systemFreeSize] as? Int64 else {
            return nil
        }
        return Int(space / 1024 / 1024) // MB
    }

    private func collectAppInfo() -> AppInfo {
        let bundle = Bundle.main
        return AppInfo(
            name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Unknown",
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            bundleId: bundle.bundleIdentifier ?? "unknown"
        )
    }

    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    private func isSimulator() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private func getBatteryLevel() -> Double? {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return level >= 0 ? Double(level) * 100 : nil
    }

    private func getNetworkType() -> String? {
        // Simplified network type detection
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)

        guard let reachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else { return nil }

        var flags: SCNetworkReachabilityFlags = []
        if !SCNetworkReachabilityGetFlags(reachability, &flags) { return nil }

        if flags.contains(.isWWAN) {
            return "cellular"
        } else if flags.contains(.reachable) {
            return "wifi"
        }

        return "unknown"
    }

    private func getCarrier() -> String? {
        // Note: CTCarrier is deprecated in iOS 16+
        return nil
    }

    private func setupSessionRecording() {
        guard let config = config else { return }
        SessionRecorder.shared.configure(
            sampleRate: config.sessionRecording.sampleRate,
            maskAllTextInputs: config.sessionRecording.maskAllTextInputs
        )
        SessionRecorder.shared.setSessionId(sessionId)
        SessionRecorder.shared.startRecording()
        log("Session recording started")
    }

    private func setupFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            self?.sendEvents()
        }
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        sendEvents()
        track("app_background")
    }

    @objc private func appWillTerminate() {
        sendEvents()
        track("app_terminate")
    }

    @objc private func appDidBecomeActive() {
        track("app_foreground")
    }

    private func setupCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let props: [String: Any] = [
                "name": exception.name.rawValue,
                "reason": exception.reason ?? "Unknown",
                "call_stack": exception.callStackSymbols.joined(separator: "\n")
            ]

            DevSkin.shared.track("crash", properties: props)
            DevSkin.shared.flush()
        }
    }

    private func trackSessionStart() {
        createSession()
        track("session_start", properties: [
            "session_id": sessionId
        ])
    }

    private func createSession() {
        guard let config = config, let device = deviceInfo else { return }

        let endpoint = "\(config.apiUrl)/v1/rum/sessions"
        guard let url = URL(string: endpoint) else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var sessionPayload: [String: Any] = [
            "sessionId": sessionId,
            "applicationId": config.appId,
            "platform": "mobile-ios",
            "anonymousId": UUID().uuidString,
            "startedAt": formatter.string(from: Date()),
            "deviceType": device.deviceType,
            "deviceModel": "\(device.manufacturer) \(device.model)",
            "osName": device.osName,
            "osVersion": device.osVersion,
            "screenWidth": device.screenWidth,
            "screenHeight": device.screenHeight,
            "apiKey": config.apiKey
        ]

        if let userId = currentUser?.id {
            sessionPayload["userId"] = userId
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(config.appId, forHTTPHeaderField: "X-App-Id")
        request.setValue("mobile", forHTTPHeaderField: "X-Platform")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: sessionPayload)
        } catch {
            log("Failed to serialize session: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                self?.log("Failed to create session: \(error)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                self?.log("Session created: \(self?.sessionId ?? ""), status: \(httpResponse.statusCode)")
            }
        }.resume()
    }

    private func log(_ message: String) {
        if config?.debug == true {
            print("[DevSkin] \(message)")
        }
    }
}

// MARK: - SwiftUI View Extension
#if canImport(SwiftUI)
import SwiftUI

public extension View {
    func trackScreen(_ name: String) -> some View {
        self.onAppear {
            DevSkin.shared.screen(name)
        }
    }

    func trackTap(_ eventName: String, properties: [String: Any]? = nil) -> some View {
        self.simultaneousGesture(TapGesture().onEnded {
            DevSkin.shared.track(eventName, properties: properties)
        })
    }
}
#endif

// MARK: - UIViewController Extension
public extension UIViewController {
    func trackScreenView() {
        let screenName = String(describing: type(of: self))
        DevSkin.shared.screen(screenName)
    }
}
