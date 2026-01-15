import UIKit
import CoreTelephony
import SystemConfiguration

// MARK: - Device Collector
public class DeviceCollector {
    public static let shared = DeviceCollector()

    private var cachedDeviceData: DeviceData?
    private var cachedAppData: AppData?

    private init() {}

    // MARK: - Collect Device Info
    public func collect() -> DeviceData {
        if let cached = cachedDeviceData {
            return cached
        }

        let screen = UIScreen.main
        let bounds = screen.bounds
        let scale = screen.scale

        let deviceData = DeviceData(
            type: getDeviceType(),
            manufacturer: "Apple",
            model: getDeviceModel(),
            os: OSInfo(name: "iOS", version: UIDevice.current.systemVersion),
            screen: ScreenInfo(
                width: Int(bounds.width * scale),
                height: Int(bounds.height * scale),
                density: Float(scale),
                orientation: getOrientation()
            ),
            memory: getMemoryInfo(),
            storage: getStorageInfo(),
            battery: getBatteryInfo(),
            network: getNetworkInfo(),
            isEmulator: isSimulator(),
            isJailbroken: isJailbroken()
        )

        cachedDeviceData = deviceData
        return deviceData
    }

    // MARK: - Collect App Info
    public func collectAppInfo() -> AppData {
        if let cached = cachedAppData {
            return cached
        }

        let bundle = Bundle.main
        let infoDictionary = bundle.infoDictionary

        let appData = AppData(
            name: infoDictionary?["CFBundleDisplayName"] as? String ?? infoDictionary?["CFBundleName"] as? String ?? "Unknown",
            version: infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
            build: infoDictionary?["CFBundleVersion"] as? String ?? "0",
            bundleId: bundle.bundleIdentifier ?? "unknown",
            installSource: getInstallSource()
        )

        cachedAppData = appData
        return appData
    }

    // MARK: - Update Orientation
    public func updateOrientation() {
        cachedDeviceData?.screen.orientation = getOrientation()
    }

    // MARK: - Private Methods
    private func getDeviceType() -> DeviceType {
        return UIDevice.current.userInterfaceIdiom == .pad ? .tablet : .phone
    }

    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        // Map identifier to human-readable name
        return mapDeviceIdentifier(identifier)
    }

    private func mapDeviceIdentifier(_ identifier: String) -> String {
        // Common device mappings
        let deviceMap: [String: String] = [
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPad13,4": "iPad Pro 11-inch (3rd gen)",
            "iPad13,5": "iPad Pro 11-inch (3rd gen)",
            // Add more as needed
        ]

        return deviceMap[identifier] ?? identifier
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

    private func getMemoryInfo() -> MemoryInfo? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = info.resident_size

        return MemoryInfo(
            total: totalMemory,
            available: totalMemory - usedMemory
        )
    }

    private func getStorageInfo() -> StorageInfo? {
        let fileManager = FileManager.default

        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
              let attributes = try? fileManager.attributesOfFileSystem(forPath: documentsURL.path) else {
            return nil
        }

        guard let totalSize = attributes[.systemSize] as? UInt64,
              let freeSize = attributes[.systemFreeSize] as? UInt64 else {
            return nil
        }

        return StorageInfo(total: totalSize, available: freeSize)
    }

    private func getBatteryInfo() -> BatteryInfo? {
        UIDevice.current.isBatteryMonitoringEnabled = true

        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return nil }

        let state = UIDevice.current.batteryState
        let isCharging = state == .charging || state == .full

        return BatteryInfo(level: level * 100, charging: isCharging)
    }

    private func getNetworkInfo() -> NetworkInfo {
        var networkType = "unknown"
        var effectiveType: String? = nil
        var carrier: String? = nil

        // Get carrier info
        let networkInfo = CTTelephonyNetworkInfo()
        if let carriers = networkInfo.serviceSubscriberCellularProviders,
           let firstCarrier = carriers.values.first {
            carrier = firstCarrier.carrierName
        }

        // Get connection type
        if let reachability = SCNetworkReachabilityCreateWithName(nil, "www.apple.com") {
            var flags: SCNetworkReachabilityFlags = []
            if SCNetworkReachabilityGetFlags(reachability, &flags) {
                if flags.contains(.isWWAN) {
                    networkType = "cellular"

                    // Get cellular generation
                    if let radioTech = networkInfo.serviceCurrentRadioAccessTechnology?.values.first {
                        effectiveType = mapRadioTech(radioTech)
                    }
                } else if flags.contains(.reachable) {
                    networkType = "wifi"
                } else {
                    networkType = "none"
                }
            }
        }

        return NetworkInfo(type: networkType, effectiveType: effectiveType, carrier: carrier)
    }

    private func mapRadioTech(_ tech: String) -> String {
        switch tech {
        case CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyCDMA1x:
            return "2g"
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA,
             CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA, CTRadioAccessTechnologyCDMAEVDORevB,
             CTRadioAccessTechnologyeHRPD:
            return "3g"
        case CTRadioAccessTechnologyLTE:
            return "4g"
        default:
            if #available(iOS 14.1, *) {
                if tech == CTRadioAccessTechnologyNRNSA || tech == CTRadioAccessTechnologyNR {
                    return "5g"
                }
            }
            return "unknown"
        }
    }

    private func isSimulator() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private func isJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        // Check for common jailbreak paths
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/"
        ]

        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }

        // Check if we can write outside sandbox
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

    private func getInstallSource() -> String {
        // Check for App Store receipt
        if let receiptURL = Bundle.main.appStoreReceiptURL {
            let receiptPath = receiptURL.path

            if receiptPath.contains("sandboxReceipt") {
                return "testflight"
            } else if FileManager.default.fileExists(atPath: receiptPath) {
                return "app_store"
            }
        }

        #if DEBUG
        return "sideload"
        #else
        return "unknown"
        #endif
    }
}
