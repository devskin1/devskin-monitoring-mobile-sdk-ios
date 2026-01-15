import Foundation

// MARK: - Network Collector
public class NetworkCollector: NSObject {
    public static let shared = NetworkCollector()

    private var isEnabled = false
    private var ignoredUrls: [String] = []
    private var captureRequestBody = false
    private var captureResponseBody = false

    private override init() {
        super.init()
    }

    public func configure(
        ignoredUrls: [String] = [],
        captureRequestBody: Bool = false,
        captureResponseBody: Bool = false
    ) {
        self.ignoredUrls = ignoredUrls
        self.captureRequestBody = captureRequestBody
        self.captureResponseBody = captureResponseBody
    }

    public func enable() {
        isEnabled = true
        URLProtocol.registerClass(DevSkinURLProtocol.self)
    }

    public func disable() {
        isEnabled = false
        URLProtocol.unregisterClass(DevSkinURLProtocol.self)
    }

    func shouldTrack(url: URL) -> Bool {
        guard isEnabled else { return false }

        let urlString = url.absoluteString

        // Check if URL should be ignored
        for pattern in ignoredUrls {
            if urlString.contains(pattern) {
                return false
            }
        }

        // Ignore DevSkin API calls
        if urlString.contains("devskin.com") || urlString.contains("/v1/rum/") || urlString.contains("/v1/sdk/") || urlString.contains("/v1/errors/") {
            return false
        }

        return true
    }

    func trackRequest(
        url: URL,
        method: String,
        statusCode: Int?,
        duration: TimeInterval,
        requestSize: Int?,
        responseSize: Int?,
        error: Error?
    ) {
        DevSkin.shared.trackNetworkRequest(
            url: url.absoluteString,
            method: method,
            statusCode: statusCode,
            duration: duration,
            requestSize: requestSize,
            responseSize: responseSize,
            error: error
        )
    }
}

// MARK: - URL Protocol for Network Interception
class DevSkinURLProtocol: URLProtocol {
    private var startTime: Date?
    private var dataTask: URLSessionDataTask?
    private var receivedData: Data?

    static let handledKey = "DevSkinURLProtocolHandled"

    override class func canInit(with request: URLRequest) -> Bool {
        // Check if already handled
        if URLProtocol.property(forKey: handledKey, in: request) != nil {
            return false
        }

        // Check if should track
        guard let url = request.url else { return false }
        return NetworkCollector.shared.shouldTrack(url: url)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            return
        }

        URLProtocol.setProperty(true, forKey: DevSkinURLProtocol.handledKey, in: mutableRequest)

        startTime = Date()
        receivedData = Data()

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        dataTask = session.dataTask(with: mutableRequest as URLRequest)
        dataTask?.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
    }
}

// MARK: - URL Session Delegate
extension DevSkinURLProtocol: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        client?.urlProtocol(self, didLoad: data)
        receivedData?.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0

        let httpResponse = task.response as? HTTPURLResponse
        let requestSize = task.originalRequest?.httpBody?.count
        let responseSize = receivedData?.count

        NetworkCollector.shared.trackRequest(
            url: task.originalRequest?.url ?? URL(string: "unknown")!,
            method: task.originalRequest?.httpMethod ?? "UNKNOWN",
            statusCode: httpResponse?.statusCode,
            duration: duration,
            requestSize: requestSize,
            responseSize: responseSize,
            error: error
        )

        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

// MARK: - URLSession Extension for Easy Tracking
public extension URLSession {
    func trackedDataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        let startTime = Date()

        return self.dataTask(with: request) { data, response, error in
            let duration = Date().timeIntervalSince(startTime)
            let httpResponse = response as? HTTPURLResponse

            NetworkCollector.shared.trackRequest(
                url: request.url ?? URL(string: "unknown")!,
                method: request.httpMethod ?? "UNKNOWN",
                statusCode: httpResponse?.statusCode,
                duration: duration,
                requestSize: request.httpBody?.count,
                responseSize: data?.count,
                error: error
            )

            completionHandler(data, response, error)
        }
    }

    func trackedDataTask(with url: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        let request = URLRequest(url: url)
        return trackedDataTask(with: request, completionHandler: completionHandler)
    }
}

// MARK: - Async/Await Support
@available(iOS 15.0, *)
public extension URLSession {
    func trackedData(from url: URL) async throws -> (Data, URLResponse) {
        let startTime = Date()

        do {
            let (data, response) = try await self.data(from: url)
            let duration = Date().timeIntervalSince(startTime)
            let httpResponse = response as? HTTPURLResponse

            NetworkCollector.shared.trackRequest(
                url: url,
                method: "GET",
                statusCode: httpResponse?.statusCode,
                duration: duration,
                requestSize: nil,
                responseSize: data.count,
                error: nil
            )

            return (data, response)
        } catch {
            let duration = Date().timeIntervalSince(startTime)

            NetworkCollector.shared.trackRequest(
                url: url,
                method: "GET",
                statusCode: nil,
                duration: duration,
                requestSize: nil,
                responseSize: nil,
                error: error
            )

            throw error
        }
    }

    func trackedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        let startTime = Date()

        do {
            let (data, response) = try await self.data(for: request)
            let duration = Date().timeIntervalSince(startTime)
            let httpResponse = response as? HTTPURLResponse

            NetworkCollector.shared.trackRequest(
                url: request.url ?? URL(string: "unknown")!,
                method: request.httpMethod ?? "UNKNOWN",
                statusCode: httpResponse?.statusCode,
                duration: duration,
                requestSize: request.httpBody?.count,
                responseSize: data.count,
                error: nil
            )

            return (data, response)
        } catch {
            let duration = Date().timeIntervalSince(startTime)

            NetworkCollector.shared.trackRequest(
                url: request.url ?? URL(string: "unknown")!,
                method: request.httpMethod ?? "UNKNOWN",
                statusCode: nil,
                duration: duration,
                requestSize: request.httpBody?.count,
                responseSize: nil,
                error: error
            )

            throw error
        }
    }
}
