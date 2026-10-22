import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// A single sequential HTTP response feeds both AVFoundation and a disk spool.
/// All mutable state and file IO are confined to `queue`, including URLSession delegates.
/// Ported from NeoDizzy (architecture after neekeetab/CachingPlayerItem, MIT); no whole-file Data buffer.
/// NeoSound: tracks run for an hour or more, so a seek far past the spooled bytes is served by its own
/// ranged request instead of waiting for the spool to get there.
nonisolated final class ProgressiveAudioLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate, @unchecked Sendable {
    static let scheme = "neosound-audio"
    /// How far ahead of the spool a request may start before it gets its own ranged request.
    static let aheadThreshold: Int64 = 2 * 1_024 * 1_024
    private let queue = DispatchQueue(label: "NeoSound.AudioSpool", qos: .userInitiated)
    private let configuration: URLSessionConfiguration
    private let url: URL
    private let file: URL
    private let writer: FileHandle
    private let reader: FileHandle
    private let maxBytes: Int64
    private let completion: @Sendable (URL?, Int64, String) -> Void
    private var session: URLSession?
    private var spoolTask: URLSessionDataTask?
    private var pending = Set<AVAssetResourceLoadingRequest>()
    /// Ranged requests for seeks ahead of the spool, by task, with the next offset each will deliver.
    private var ahead: [Int: (request: AVAssetResourceLoadingRequest, offset: Int64)] = [:]
    private var received: Int64 = 0
    private var expected: Int64 = -1
    private var contentType: String?
    private var fileExtension: String
    private var finished = false
    private var failure: Error?
    private var started = false

    init(url: URL, directory: URL, maxBytes: Int64, configuration: URLSessionConfiguration = .ephemeral,
         completion: @escaping @Sendable (URL?, Int64, String) -> Void) throws {
        self.url = url; self.maxBytes = maxBytes; self.completion = completion; self.configuration = configuration
        fileExtension = url.pathExtension.lowercased()
        file = directory.appendingPathComponent(UUID().uuidString + ".partial")
        guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw ASMRAPIError.invalidResponse }
        writer = try FileHandle(forWritingTo: file)
        reader = try FileHandle(forReadingFrom: file)
        super.init()
    }
    func makeItem() -> AVPlayerItem {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.scheme = Self.scheme
        let asset = AVURLAsset(url: components.url!)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return AVPlayerItem(asset: asset)
    }
    func cancel() { queue.async { self.finish(URLError(.cancelled)) } }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        pending.insert(request)
        if !started && !finished {
            started = true
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30
            let delegateQueue = OperationQueue(); delegateQueue.maxConcurrentOperationCount = 1; delegateQueue.underlyingQueue = queue
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
            self.session = session
            var request = URLRequest(url: url)
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let task = session.dataTask(with: request)
            spoolTask = task
            task.resume()
        }
        fulfill(); return true
    }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        pending.remove(request)
        for (id, fetch) in ahead where fetch.request == request {
            ahead[id] = nil
            session?.getAllTasks { tasks in tasks.first { $0.taskIdentifier == id }?.cancel() }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let fetch = ahead[dataTask.taskIdentifier] {
            guard (response as? HTTPURLResponse)?.statusCode == 206 else {
                completionHandler(.cancel); ahead[dataTask.taskIdentifier] = nil
                fetch.request.finishLoading(with: ASMRAPIError.invalidResponse); pending.remove(fetch.request); return
            }
            completionHandler(.allow); return
        }
        guard !finished, let response = response as? HTTPURLResponse, response.statusCode == 200,
              !Self.isErrorContentType(response.mimeType), response.expectedContentLength != 0,
              response.expectedContentLength <= maxBytes else {
            completionHandler(.cancel); finish(ASMRAPIError.invalidResponse); return
        }
        expected = response.expectedContentLength
        let type = response.mimeType.flatMap { UTType(mimeType: $0) } ?? UTType(filenameExtension: fileExtension)
        contentType = type?.identifier ?? UTType.audio.identifier
        if let ext = type?.preferredFilenameExtension { fileExtension = ext }
        completionHandler(.allow); fulfill()
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let fetch = ahead[dataTask.taskIdentifier] {
            fetch.request.dataRequest?.respond(with: data)
            ahead[dataTask.taskIdentifier]?.offset = fetch.offset + Int64(data.count)
            return
        }
        guard !finished else { return }
        do {
            guard received + Int64(data.count) <= maxBytes else { throw ASMRAPIError.invalidResponse }
            try writer.write(contentsOf: data); received += Int64(data.count)
            fulfill()
        } catch { finish(error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let fetch = ahead.removeValue(forKey: task.taskIdentifier) {
            if let error, (error as? URLError)?.code != .cancelled { fetch.request.finishLoading(with: error) }
            else if error == nil { fetch.request.finishLoading() }
            pending.remove(fetch.request); return
        }
        guard task == spoolTask else { return }
        if let error { finish(error) }
        else if received <= 0 || (expected >= 0 && received != expected) { finish(ASMRAPIError.invalidResponse) }
        else { finish(nil) }
    }

    private func finish(_ error: Error?) {
        guard !finished else { return }
        finished = true; failure = error
        if expected < 0 { expected = received }
        try? writer.synchronize()
        // Ranged requests keep serving a seek ahead even after a cancelled spool; invalidation lets them finish.
        if error == nil || ahead.isEmpty { session?.invalidateAndCancel(); session = nil } else { session?.finishTasksAndInvalidate() }
        fulfill()
        // Hand off a separate file so rapid switching cannot delete it before the index commits.
        if error == nil {
            let ready = file.deletingPathExtension().appendingPathExtension("ready")
            do { try FileManager.default.copyItem(at: file, to: ready); completion(ready, received, fileExtension) }
            catch { completion(nil, 0, fileExtension) }
        } else { completion(nil, 0, fileExtension) }
    }
    private func fulfill() {
        let fetching = Set(ahead.values.map(\.request))
        for request in pending where !fetching.contains(request) {
            if let failure { request.finishLoading(with: failure); pending.remove(request); continue }
            if let info = request.contentInformationRequest, let contentType, expected >= 0 {
                info.contentType = contentType; info.contentLength = expected; info.isByteRangeAccessSupported = true
            }
            guard let data = request.dataRequest else {
                if contentType != nil && expected >= 0 { request.finishLoading(); pending.remove(request) }; continue
            }
            var offset = max(data.requestedOffset, data.currentOffset)
            let end = data.requestsAllDataToEndOfResource ? (expected >= 0 ? expected : Int64.max) : data.requestedOffset + Int64(data.requestedLength)
            if !finished, contentType != nil, expected > 0, offset > received + Self.aheadThreshold, offset < expected {
                fetchAhead(request, from: offset, to: min(end, expected)); continue
            }
            do {
                while offset < min(received, end) {
                    try reader.seek(toOffset: UInt64(offset))
                    let chunk = try reader.read(upToCount: Int(min(64 * 1_024, min(received, end) - offset))) ?? Data()
                    guard !chunk.isEmpty else { throw ASMRAPIError.invalidResponse }
                    data.respond(with: chunk); offset += Int64(chunk.count)
                }
                if offset >= end || (finished && offset >= received) { request.finishLoading(); pending.remove(request) }
            } catch { request.finishLoading(with: error); pending.remove(request) }
        }
    }
    private func fetchAhead(_ loading: AVAssetResourceLoadingRequest, from start: Int64, to end: Int64) {
        guard let session, end > start else { return }
        var request = URLRequest(url: url)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("bytes=\(start)-\(end - 1)", forHTTPHeaderField: "Range")
        let task = session.dataTask(with: request)
        ahead[task.taskIdentifier] = (loading, start)
        task.resume()
    }
    static func isErrorContentType(_ mime: String?) -> Bool {
        guard let mime = mime?.lowercased() else { return false }
        return mime.hasPrefix("text/") || mime.contains("json") || mime.contains("html")
    }
    deinit {
        try? writer.close(); try? reader.close()
        try? FileManager.default.removeItem(at: file)
    }
}
