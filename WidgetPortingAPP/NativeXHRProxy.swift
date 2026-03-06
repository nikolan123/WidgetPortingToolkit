//
//  NativeXHRProxy.swift
//  WidgetPortingAPP
//
//  Created by Niko on 9.09.25.
//

import WebKit

// MARK: - NativeXHRProxy
final class NativeXHRProxy: NSObject, URLSessionDataDelegate {
    private weak var owner: WebView.Coordinator?
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private var tasksById: [Int: URLSessionDataTask] = [:]
    private var buffers: [Int: Data] = [:]
    private var responses: [Int: HTTPURLResponse] = [:]

    init(owner: WebView.Coordinator) {
        self.owner = owner
        super.init()
    }

    func start(id: Int, request: URLRequest) {
        // Clean any previous remnants just in case
        buffers[id] = Data()
        responses[id] = nil

        let task = session.dataTask(with: request)
        tasksById[id] = task
        task.resume()
    }

    func abort(id: Int) {
        guard let t = tasksById[id] else { return }
        t.cancel()
        tasksById.removeValue(forKey: id)
        buffers.removeValue(forKey: id)
        responses.removeValue(forKey: id)
        owner?.sendXHRCallback([
            "id": id,
            "type": "abort"
        ])
    }

    // MARK: - URLSessionDataDelegate
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let id = idFor(task: dataTask)
        if let http = response as? HTTPURLResponse {
            responses[id] = http
            owner?.sendXHRCallback([
                "id": id,
                "type": "headers",
                "status": http.statusCode,
                "statusText": HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                "headers": headersString(from: http)
            ])
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let id = idFor(task: dataTask)
        if buffers[id] == nil { buffers[id] = Data() }
        buffers[id]?.append(data)

        // Signal LOADING (readyState 3). We don't stream partial text to avoid huge JS copies.
        owner?.sendXHRCallback([
            "id": id,
            "type": "loading"
        ])
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = idFor(task: task)
        defer {
            tasksById.removeValue(forKey: id)
            buffers.removeValue(forKey: id)
            responses.removeValue(forKey: id)
        }

        if let err = error as NSError? {
            // Distinguish timeout vs generic error if desired
            let isTimeout = (err.domain == NSURLErrorDomain && err.code == NSURLErrorTimedOut)
            owner?.sendXHRCallback([
                "id": id,
                "type": isTimeout ? "timeout" : "error"
            ])
            return
        }

        let http = responses[id]
        let status = http?.statusCode ?? 0
        let text = String(data: buffers[id] ?? Data(), encoding: .utf8) ?? ""
        owner?.sendXHRCallback([
            "id": id,
            "type": "done",
            "ok": (200...299).contains(status),
            "status": status,
            "statusText": HTTPURLResponse.localizedString(forStatusCode: status),
            "headers": headersString(from: http),
            "text": text
        ])
    }

    // MARK: - Helpers
    private func idFor(task: URLSessionTask) -> Int {
        // Find the id for a task (linear, tiny map)
        for (k, v) in tasksById where v.taskIdentifier == task.taskIdentifier {
            return k
        }
        return -1
    }

    private func headersString(from response: HTTPURLResponse?) -> String {
        guard let response else { return "" }
        // Build "Key: Value\r\n" like XHR
        let fields = response.allHeaderFields
        // Maintain stable ordering by key name for determinism
        let pairs: [(String, String)] = fields.compactMap { (k, v) in
            guard let key = k as? String else { return nil }
            return (key, String(describing: v))
        }.sorted { $0.0.lowercased() < $1.0.lowercased() }
        return pairs.map { "\($0): \($1)" }.joined(separator: "\r\n")
    }
}
