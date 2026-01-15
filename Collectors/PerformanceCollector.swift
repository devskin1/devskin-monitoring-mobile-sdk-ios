import Foundation
import UIKit
import QuartzCore

// MARK: - Performance Collector
public class PerformanceCollector {
    public static let shared = PerformanceCollector()

    private var appLaunchTime: CFAbsoluteTime?
    private var screenRenderTimes: [String: CFAbsoluteTime] = [:]
    private var displayLink: CADisplayLink?
    private var frameCount = 0
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var fpsValues: [Double] = []

    private init() {}

    // MARK: - App Launch Tracking
    public func trackAppLaunchStart() {
        appLaunchTime = CFAbsoluteTimeGetCurrent()
    }

    public func trackAppLaunchEnd() {
        guard let startTime = appLaunchTime else { return }

        let launchDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 // ms

        DevSkin.shared.trackPerformance(
            metric: "app_launch_time",
            value: launchDuration,
            unit: "ms",
            context: [
                "cold_start": true
            ]
        )

        appLaunchTime = nil
    }

    // MARK: - Screen Render Tracking
    public func trackScreenRenderStart(_ screenName: String) {
        screenRenderTimes[screenName] = CFAbsoluteTimeGetCurrent()
    }

    public func trackScreenRenderEnd(_ screenName: String) {
        guard let startTime = screenRenderTimes[screenName] else { return }

        let renderDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 // ms

        DevSkin.shared.trackPerformance(
            metric: "screen_render_time",
            value: renderDuration,
            unit: "ms",
            context: [
                "screen_name": screenName
            ]
        )

        screenRenderTimes.removeValue(forKey: screenName)
    }

    // MARK: - FPS Monitoring
    public func startFPSMonitoring() {
        displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
        displayLink?.add(to: .main, forMode: .common)
    }

    public func stopFPSMonitoring() {
        displayLink?.invalidate()
        displayLink = nil

        // Send average FPS
        if !fpsValues.isEmpty {
            let avgFPS = fpsValues.reduce(0, +) / Double(fpsValues.count)
            DevSkin.shared.trackPerformance(
                metric: "average_fps",
                value: avgFPS,
                unit: "fps"
            )
        }

        fpsValues.removeAll()
    }

    @objc private func handleDisplayLink(_ displayLink: CADisplayLink) {
        if lastFrameTimestamp == 0 {
            lastFrameTimestamp = displayLink.timestamp
            return
        }

        frameCount += 1

        let elapsed = displayLink.timestamp - lastFrameTimestamp
        if elapsed >= 1.0 {
            let fps = Double(frameCount) / elapsed
            fpsValues.append(fps)

            // Track slow frames (below 30 FPS)
            if fps < 30 {
                DevSkin.shared.trackPerformance(
                    metric: "slow_frame",
                    value: fps,
                    unit: "fps"
                )
            }

            frameCount = 0
            lastFrameTimestamp = displayLink.timestamp
        }
    }

    // MARK: - Memory Tracking
    public func trackMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let usedMemory = Double(info.resident_size) / 1024 / 1024 // MB

            DevSkin.shared.trackPerformance(
                metric: "memory_usage",
                value: usedMemory,
                unit: "MB"
            )
        }
    }

    // MARK: - CPU Tracking
    public func trackCPUUsage() {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let result = task_threads(mach_task_self_, &threadList, &threadCount)

        if result != KERN_SUCCESS {
            return
        }

        var totalCPU: Double = 0

        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_BASIC_INFO_COUNT)

            let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    thread_info(threadList![i], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                }
            }

            if infoResult == KERN_SUCCESS {
                if threadInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalCPU += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100
                }
            }
        }

        DevSkin.shared.trackPerformance(
            metric: "cpu_usage",
            value: totalCPU,
            unit: "percent"
        )

        // Deallocate thread list
        if let threads = threadList {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride))
        }
    }

    // MARK: - Disk Usage
    public func trackDiskUsage() {
        let fileManager = FileManager.default

        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
              let attributes = try? fileManager.attributesOfFileSystem(forPath: documentsURL.path) else {
            return
        }

        if let freeSize = attributes[.systemFreeSize] as? Int64,
           let totalSize = attributes[.systemSize] as? Int64 {

            let usedSize = totalSize - freeSize
            let usedPercentage = Double(usedSize) / Double(totalSize) * 100

            DevSkin.shared.trackPerformance(
                metric: "disk_usage",
                value: usedPercentage,
                unit: "percent",
                context: [
                    "total_gb": Double(totalSize) / 1024 / 1024 / 1024,
                    "free_gb": Double(freeSize) / 1024 / 1024 / 1024
                ]
            )
        }
    }
}

// MARK: - View Controller Performance Extension
public extension UIViewController {
    func trackViewControllerPerformance() {
        let screenName = String(describing: type(of: self))
        PerformanceCollector.shared.trackScreenRenderStart(screenName)

        DispatchQueue.main.async {
            PerformanceCollector.shared.trackScreenRenderEnd(screenName)
        }
    }
}
