import Foundation
import Observation
import AVFoundation

@Observable final class VersionDownloadStore {
    static let shared = VersionDownloadStore()
    private(set) var downloads: [VersionDownload] = []
    private(set) var issue: String?
    private(set) var progress: [UUID: Double] = [:]
    private(set) var transfers: [UUID: DownloadTransfer] = [:]
    let directory: URL
    @ObservationIgnored private var store: ASMRStore?
    @ObservationIgnored private var transport: DownloadTransport?
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var operations: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var restoring = false
    @ObservationIgnored private var active = Set<UUID>()
    @ObservationIgnored private var completedWorks = Set<Int>()
    private(set) var revision = 0

    init(directory: URL = URL.documentsDirectory.appendingPathComponent("Downloads",isDirectory:true)) {
        self.directory = directory
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        if let data = try? Data(contentsOf:directory.appendingPathComponent("index.json")),
           let saved = try? JSONDecoder().decode([VersionDownload].self,from:data) { downloads = saved }
        validate()
    }
    func start(store: ASMRStore) {
        self.store = store
        guard transport == nil else { return }
        let transport = DownloadTransport(directory:directory.appendingPathComponent(".incoming"))
        self.transport = transport; restoring = true
        listener = Task { [weak self] in
            for await event in transport.events { await self?.handle(event) }
        }
        Task {
            let tasks = await transport.tasks()
            let known = Set(downloads.filter { !$0.paused }.flatMap(\.files).compactMap(\.attemptID))
            let taskIDs = Set(tasks.compactMap { $0.taskDescription.flatMap(UUID.init(uuidString:)) })
            for task in tasks {
                if let id = task.taskDescription.flatMap(UUID.init(uuidString:)), known.contains(id) {
                    active.insert(id); if task.state == .suspended { task.resume() }
                } else { task.cancel() }
            }
            let pending = downloads.flatMap(\.files).filter { $0.state == .downloading }.compactMap(\.attemptID)
            for id in pending {
                guard let (j,f) = location(id) else { continue }
                if taskIDs.contains(id), known.contains(id) { continue }
                // A crash may occur after the delegate moved its file but before the manifest commit.
                let raw = directory.appendingPathComponent(".incoming/" + id.uuidString)
                let typed = raw.appendingPathExtension((downloads[j].files[f].filename as NSString).pathExtension)
                let file = FileManager.default.fileExists(atPath:typed.path) ? typed : raw
                if let size = try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize {
                    await finish(id,file:file,bytes:Int64(size))
                } else if let (j,f) = location(id) {
                    clearTransfer(downloads[j].files[f].id)
            downloads[j].files[f].state = .queued; downloads[j].files[f].attemptID = nil
                }
            }
            // Repair interrupted records from before an attempt was persisted.
            for j in downloads.indices {
                for f in downloads[j].files.indices where downloads[j].files[f].state == .downloading && downloads[j].files[f].attemptID == nil {
                    downloads[j].files[f].state = .queued
                }
            }
            restoring = false; save(); pump()
        }
    }
    func job(workID: Int, version: TrackVersion) -> VersionDownload? {
        downloads.first { $0.work.id == workID && $0.version == version }
    }
    func hasCompleteVersion(_ workID: Int) -> Bool { _ = revision; return completedWorks.contains(workID) }
    var completedWorkCount: Int { _ = revision; return completedWorks.count }
    func fileURL(_ file: DownloadFile, in job: VersionDownload) -> URL {
        directory.appendingPathComponent(job.id.uuidString).appendingPathComponent(file.filename)
    }
    private func valid(_ file: DownloadFile, in job: VersionDownload) -> Bool {
        file.state == .completed && file.bytes > 0 && (try? fileURL(file,in:job).resourceValues(forKeys:[.fileSizeKey]).fileSize).map(Int64.init) == file.bytes
    }
    func localEntries(workID: Int) -> [TrackEntry] {
        var keys = Set<String>()
        return downloads.filter { $0.work.id == workID }.flatMap { job in
            job.files.compactMap { file in
                let saved = file.track
                let key = saved.hash ?? "\(workID)|\(saved.path)|\(saved.title)"
                guard valid(file,in:job), keys.insert(key).inserted else { return nil }
                return TrackEntry(id:saved.id,node:ASMRNode(localURL:fileURL(file,in:job),title:saved.title,type:file.type,
                    hash:saved.hash,duration:saved.duration,size:file.bytes),path:saved.path)
            }
        }
    }
    func localFile(for track: TrackEntry, workID: Int) -> URL? {
        let key = AudioPlaybackCache.key(for:track,workID:workID)
        return localEntries(workID:workID).first { AudioPlaybackCache.key(for:$0,workID:workID) == key }?.node.streamURL
    }
    func cover(workID: Int) -> URL? {
        for job in downloads where job.work.id == workID {
            if let name = job.coverFilename, name == URL(fileURLWithPath:name).lastPathComponent {
                let url = directory.appendingPathComponent(job.id.uuidString).appendingPathComponent(name)
                if FileManager.default.fileExists(atPath:url.path) { return url }
            }
        }
        return nil
    }
    func enqueue(work: ASMRWork, version: TrackVersion, tracks: [TrackEntry], allEntries: [TrackEntry]) {
        guard !tracks.isEmpty, job(workID:work.id,version:version) == nil else { return }
        var entries = tracks
        for track in tracks {
            if let subtitle = SubtitleMatcher.match(track,in:allEntries), !entries.contains(where: { $0.id == subtitle.id }) { entries.append(subtitle) }
        }
        let files = entries.map { DownloadFile(id:UUID(),track:PlaylistTrack(entry:$0,work:work),type:$0.node.type,expectedBytes:$0.node.size) }
        let job = VersionDownload(id:UUID(),work:work,version:version,created:.now,files:files)
        downloads.insert(job,at:0)
        guard save() else { downloads.removeAll { $0.id == job.id }; return }
        pump()
        Task { await saveCover(job) }
    }
    func pause(_ id: UUID) {
        guard let j = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[j].paused = true
        let attempts = Set(downloads[j].files.compactMap(\.attemptID))
        for f in downloads[j].files.indices where downloads[j].files[f].state == .downloading {
            clearTransfer(downloads[j].files[f].id)
            downloads[j].files[f].state = .queued; downloads[j].files[f].attemptID = nil
        }
        for attempt in attempts { operations.removeValue(forKey:attempt)?.cancel(); active.remove(attempt) }
        save()
        Task { for task in await transport?.tasks() ?? [] where task.taskDescription.flatMap(UUID.init(uuidString:)).map(attempts.contains) == true { task.cancel() } }
        pump()
    }
    func retry(_ id: UUID) {
        guard let j = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[j].paused = false
        for f in downloads[j].files.indices where downloads[j].files[f].state == .failed {
            downloads[j].files[f].state = .queued; downloads[j].files[f].failure = nil
        }
        save(); pump()
    }
    func remove(_ id: UUID) {
        pause(id)
        do {
            let folder = directory.appendingPathComponent(id.uuidString)
            if FileManager.default.fileExists(atPath:folder.path) { try FileManager.default.removeItem(at:folder) }
            for file in downloads.first(where:{ $0.id == id })?.files ?? [] { clearTransfer(file.id) }
            downloads.removeAll { $0.id == id }; save()
        } catch { issue = "删除失败，请稍后重试。" }
    }
    func validate() {
        for j in downloads.indices {
            let snapshot = downloads[j]
            for f in downloads[j].files.indices where downloads[j].files[f].state == .completed && !valid(downloads[j].files[f],in:snapshot) {
                downloads[j].files[f].state = .failed; downloads[j].files[f].failure = "本地文件缺失或不完整，请重试。"
            }
        }
        save()
    }
    private func location(_ attempt: UUID) -> (Int, Int)? {
        for j in downloads.indices {
            if let f = downloads[j].files.firstIndex(where: { $0.attemptID == attempt }) { return (j,f) }
        }
        return nil
    }
    private func pump() {
        guard !restoring, store != nil, transport != nil else { return }
        while active.count < 3 {
            guard let j = downloads.firstIndex(where: { !$0.paused && $0.files.contains { $0.state == .queued } }),
                  let f = downloads[j].files.firstIndex(where: { $0.state == .queued }) else { break }
            let attempt = UUID()
            downloads[j].files[f].attemptID = attempt; downloads[j].files[f].state = .downloading
            active.insert(attempt)
            guard save() else { active.remove(attempt); downloads[j].files[f].state = .failed; break }
            operations[attempt] = Task { await begin(attempt) }
        }
    }
    private func begin(_ attempt: UUID) async {
        defer { operations[attempt] = nil }
        guard let (j,f) = location(attempt), let store else { return }
        let job = downloads[j], file = job.files[f]
        do {
            let staging = directory.appendingPathComponent(".incoming/" + attempt.uuidString)
            if file.type == "audio", let cached = try await AudioPlaybackCache.shared.exportOriginal(for:file.track,expectedBytes:file.expectedBytes,to:staging) {
                await finish(attempt,file:cached,bytes:Int64(try cached.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0))
                if downloads.first(where: { $0.id == job.id })?.files.first(where: { $0.id == file.id })?.state == .failed {
                    AudioPlaybackCache.shared.remove(file.track.hash ?? "\(job.work.id)|\(file.track.path)|\(file.track.title)")
                }
                return
            }
            let entries = TrackEntry.flatten(try await store.tracks(job.work.id,refresh:true),workID:job.work.id)
            try Task.checkCancellation()
            guard location(attempt) != nil else { return }
            // Hash is authoritative; never substitute a changed file merely because its position matches.
            let entry = entries.first { entry in
                if let hash = file.track.hash { return entry.node.hash == hash }
                return entry.path == file.track.path && entry.title == file.track.title
            }
            guard let entry, let url = entry.node.mediaDownloadUrl ?? entry.node.mediaStreamUrl else { throw ASMRAPIError.invalidResponse }
            transport?.start(url,id:attempt)
        } catch {
            try? FileManager.default.removeItem(at:directory.appendingPathComponent(".incoming/" + attempt.uuidString))
            fail(attempt); pump()
        }
    }
    func handle(_ event: DownloadEvent) async {
        switch event {
        case let .progress(id,written,total):
            if let (j,f) = location(id) {
                let fileID = downloads[j].files[f].id
                transfers[fileID,default:DownloadTransfer()].record(written:written,total:total,at:ProcessInfo.processInfo.systemUptime)
                progress[fileID] = total > 0 ? min(1,Double(written)/Double(total)) : 0
            }
        case let .finished(id,file,bytes): await finish(id,file:file,bytes:bytes)
        case let .failed(id): fail(id)
        case .backgroundFinished:
            let completion = DownloadAppDelegate.completion; DownloadAppDelegate.completion = nil; completion?()
        }
        pump()
    }
    private func clearTransfer(_ id: UUID) {
        transfers[id] = nil; progress[id] = nil
    }
    func transferSummary(for job: VersionDownload, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> DownloadTransferSummary {
        var received: Int64 = 0, total: Int64 = 0
        var known = true
        var speed = 0.0
        for file in job.files {
            if file.state == .completed { received += file.bytes; total += file.bytes; continue }
            let transfer = transfers[file.id]
            received += transfer?.received ?? 0
            if let size = transfer?.total ?? file.expectedBytes, size > 0 { total += size }
            else { known = false }
            if !job.paused && file.state == .downloading { speed += transfer?.speed(at:time) ?? 0 }
        }
        return DownloadTransferSummary(received:received,total:known ? total : nil,bytesPerSecond:speed)
    }

    private func fail(_ id: UUID) {
        active.remove(id)
        guard let (j,f) = location(id) else { return }
        clearTransfer(downloads[j].files[f].id)
        downloads[j].files[f].state = .failed; downloads[j].files[f].attemptID = nil
        downloads[j].files[f].failure = "下载失败，请检查网络或可用空间后重试。"
        save()
    }
    private func finish(_ id: UUID, file: URL, bytes: Int64) async {
        var file = file
        defer { try? FileManager.default.removeItem(at:file); active.remove(id); pump() }
        guard let (j,f) = location(id) else { return }
        let job = downloads[j], entry = job.files[f]
        do {
            guard bytes > 0, entry.expectedBytes == nil || entry.expectedBytes == bytes else { throw ASMRAPIError.invalidResponse }
            if entry.type == "audio" {
                // AVFoundation needs the actual extension for some containers (notably WAV).
                let ext = (entry.filename as NSString).pathExtension
                if file.pathExtension != ext {
                    let typed = file.appendingPathExtension(ext)
                    try? FileManager.default.removeItem(at:typed)
                    try FileManager.default.moveItem(at:file,to:typed); file = typed
                }
                guard try await AVURLAsset(url:file).load(.isPlayable) else { throw ASMRAPIError.invalidResponse }
            } else {
                guard bytes < 2_000_000, !WebVTT.parseSubtitle(try Data(contentsOf:file),filename:entry.track.title).isEmpty else { throw ASMRAPIError.invalidResponse }
            }
            guard let (j,f) = location(id) else { return }
            let destination = fileURL(entry,in:job)
            try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
            try? FileManager.default.removeItem(at:destination)
            try FileManager.default.moveItem(at:file,to:destination)
            downloads[j].files[f].bytes = bytes; downloads[j].files[f].state = .completed
            downloads[j].files[f].attemptID = nil; downloads[j].files[f].failure = nil
            clearTransfer(entry.id)
            if save(), entry.type == "audio" {
                AudioPlaybackCache.shared.remove(entry.track.hash ?? "\(job.work.id)|\(entry.track.path)|\(entry.track.title)")
            }
        } catch { fail(id) }
    }
    private func saveCover(_ job: VersionDownload) async {
        guard let url = job.work.coverURL else { return }
        do {
            let (temp,response) = try await URLSession.shared.download(from:url)
            defer { try? FileManager.default.removeItem(at:temp) }
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let size = try temp.resourceValues(forKeys:[.fileSizeKey]).fileSize, size < 20_000_000,
                  let j = downloads.firstIndex(where: { $0.id == job.id }) else { return }
            let target = directory.appendingPathComponent(job.id.uuidString).appendingPathComponent("cover.jpg")
            try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
            try? FileManager.default.removeItem(at:target)
            try FileManager.default.moveItem(at:temp,to:target)
            downloads[j].coverFilename = "cover.jpg"; save()
        } catch { /* Artwork failure must not discard audio. */ }
    }
    @discardableResult private func save() -> Bool {
        do {
            try JSONEncoder().encode(downloads).write(to:directory.appendingPathComponent("index.json"),options:.atomic)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var folder = directory; try folder.setResourceValues(values)
            completedWorks = Set(downloads.filter(\.isComplete).map { $0.work.id }); revision += 1
            issue = nil; return true
        } catch {
            completedWorks = []; revision += 1
            issue = "下载记录保存失败，请检查可用空间。"; return false
        }
    }
}
