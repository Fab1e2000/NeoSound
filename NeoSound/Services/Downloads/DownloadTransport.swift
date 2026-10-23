import Foundation
import UIKit

nonisolated enum DownloadEvent: Sendable {
    case progress(UUID, Int64, Int64)
    case finished(UUID, URL, Int64)
    case failed(UUID)
    case backgroundFinished
}

/// Delegate callbacks move temporary files synchronously, before URLSession deletes them.
nonisolated final class DownloadTransport: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let identifier = "com.elsterlee.NeoSound.version-downloads"
    let events: AsyncStream<DownloadEvent>
    private let continuation: AsyncStream<DownloadEvent>.Continuation
    private let directory: URL
    private var session: URLSession!
    init(directory: URL) {
        self.directory = directory
        let stream = AsyncStream<DownloadEvent>.makeStream()
        events = stream.stream; continuation = stream.continuation
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false
        config.sessionSendsLaunchEvents = true; config.isDiscretionary = false
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 24 * 60 * 60
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration:config,delegate:self,delegateQueue:queue)
    }
    func tasks() async -> [URLSessionTask] { await session.allTasks }
    func start(_ url: URL, id: UUID) {
        let task = session.downloadTask(with:url)
        task.taskDescription = id.uuidString; task.resume()
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) {
            continuation.yield(.progress(id,totalBytesWritten,totalBytesExpectedToWrite))
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200,
                  !ProgressiveAudioLoader.isErrorContentType(response.mimeType) || response.mimeType == "text/vtt" || response.mimeType == "text/plain" else { throw ASMRAPIError.invalidResponse }
            let size = Int64(try location.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)
            guard size > 0, response.expectedContentLength < 0 || size == response.expectedContentLength else { throw ASMRAPIError.invalidResponse }
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let target = directory.appendingPathComponent(id.uuidString)
            try? FileManager.default.removeItem(at:target)
            try FileManager.default.moveItem(at:location,to:target)
            continuation.yield(.finished(id,target,size))
        } catch { continuation.yield(.failed(id)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if error != nil, let id = task.taskDescription.flatMap(UUID.init(uuidString:)) { continuation.yield(.failed(id)) }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) { continuation.yield(.backgroundFinished) }
}

final class DownloadAppDelegate: NSObject, UIApplicationDelegate {
    static var completion: (() -> Void)?
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == DownloadTransport.identifier else { completionHandler(); return }
        Self.completion = completionHandler
        VersionDownloadStore.shared.start(store:ASMRStore())
    }
}
