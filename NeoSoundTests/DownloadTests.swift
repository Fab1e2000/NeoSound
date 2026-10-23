import Foundation
import Testing
@testable import NeoSound

@Suite("版本下载", .serialized)
@MainActor struct DownloadTests {
    private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("version-download-tests-" + UUID().uuidString) }
    private func entry(_ name: String, type: String = "audio") throws -> TrackEntry {
        let object: [String:Any] = ["title":name,"type":type,"hash":name,"mediaStreamUrl":"https://example.com/stream?token=private","mediaDownloadUrl":"https://example.com/download?token=private","size":100]
        return TrackEntry(id:name,node:try JSONDecoder().decode(ASMRNode.self,from:JSONSerialization.data(withJSONObject:object)),path:"MP3")
    }
    private var work: ASMRWork { ASMRWork(id:7,title:"作品") }
    private var version: TrackVersion { TrackVersion(format:"MP3",withSE:true) }

    @Test func transferSpeedUsesByteDeltasAndExpiresWhenStalled() {
        var transfer = DownloadTransfer()
        transfer.record(written:100,total:1000,at:10)
        transfer.record(written:500,total:1000,at:12)
        #expect(transfer.speed(at:12) == 200)
        #expect(transfer.speed(at:15) == 0)
        transfer.record(written:50,total:-1,at:16)
        #expect(transfer.received == 50)
        #expect(transfer.total == nil)
        #expect(transfer.speed(at:16) == 0)
    }

    @Test func liveProgressCombinesSavedBytesAndClearsCancelledAttempts() async throws {
        let dir = folder(); defer { try? FileManager.default.removeItem(at:dir) }
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let saved = DownloadFile(id:UUID(),track:PlaylistTrack(entry:try entry("01.mp3"),work:work),type:"audio",expectedBytes:100,bytes:100,state:.completed)
        let attempt = UUID()
        let active = DownloadFile(id:UUID(),track:PlaylistTrack(entry:try entry("02.mp3"),work:work),type:"audio",expectedBytes:100,attemptID:attempt,state:.downloading)
        let job = VersionDownload(id:UUID(),work:work,version:version,created:.now,files:[saved,active])
        let savedURL = dir.appendingPathComponent(job.id.uuidString).appendingPathComponent(saved.filename)
        try FileManager.default.createDirectory(at:savedURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data(repeating:1,count:100).write(to:savedURL)
        try JSONEncoder().encode([job]).write(to:dir.appendingPathComponent("index.json"))
        let store = VersionDownloadStore(directory:dir)
        await store.handle(.progress(attempt,50,100))
        let summary = store.transferSummary(for:store.downloads[0])
        #expect(summary.received == 150)
        #expect(summary.total == 200)
        #expect(summary.fraction == 0.75)
        store.pause(job.id)
        await store.handle(.progress(attempt,90,100))
        #expect(store.transfers[active.id] == nil)
        #expect(store.transferSummary(for:store.downloads[0]).received == 100)
        #expect(store.transferSummary(for:store.downloads[0]).bytesPerSecond == 0)
    }

    @Test func onlySelectedVersionIsQueuedAndSignedURLsAreNotPersisted() throws {
        let dir = folder(); defer { try? FileManager.default.removeItem(at:dir) }
        let store = VersionDownloadStore(directory:dir)
        let mp3 = try entry("01.mp3"), wav = try entry("01.wav"), subtitle = try entry("01.vtt",type:"text")
        store.enqueue(work:work,version:version,tracks:[mp3],allEntries:[mp3,wav,subtitle])
        store.enqueue(work:work,version:version,tracks:[mp3],allEntries:[mp3,wav,subtitle])
        #expect(store.downloads.count == 1)
        #expect(store.downloads[0].audio.map(\.track.title) == ["01.mp3"])
        #expect(store.downloads[0].files.contains { $0.track.title == "01.vtt" })
        let saved = try String(contentsOf:dir.appendingPathComponent("index.json"),encoding:.utf8)
        #expect(!saved.contains("token=private"))
        #expect(!store.hasCompleteVersion(work.id))
    }


    @Test func completeVersionSurvivesRestartButMissingAudioRemovesBadge() throws {
        let dir = folder(); defer { try? FileManager.default.removeItem(at:dir) }
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let track = PlaylistTrack(entry:try entry("01.mp3"),work:work)
        let audio = DownloadFile(id:UUID(),track:track,type:"audio",expectedBytes:100,bytes:100,state:.completed)
        let subtitle = DownloadFile(id:UUID(),track:PlaylistTrack(entry:try entry("01.vtt",type:"text"),work:work),type:"text",expectedBytes:nil,state:.failed)
        let job = VersionDownload(id:UUID(),work:work,version:version,created:.now,files:[audio,subtitle])
        let file = dir.appendingPathComponent(job.id.uuidString).appendingPathComponent(audio.filename)
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data(repeating:1,count:100).write(to:file)
        try JSONEncoder().encode([job]).write(to:dir.appendingPathComponent("index.json"))
        let restored = VersionDownloadStore(directory:dir)
        #expect(restored.hasCompleteVersion(work.id)) // optional subtitle failure is independent
        #expect(restored.localEntries(workID:work.id).first?.node.streamURL == file)
        try Data([1]).write(to:file)
        restored.validate()
        #expect(!restored.hasCompleteVersion(work.id))
        #expect(restored.localEntries(workID:work.id).isEmpty)
    }

    @Test func partialVersionIsNotComplete() throws {
        let first = DownloadFile(id:UUID(),track:PlaylistTrack(entry:try entry("01.mp3"),work:work),type:"audio",expectedBytes:100,bytes:100,state:.completed)
        let second = DownloadFile(id:UUID(),track:PlaylistTrack(entry:try entry("02.mp3"),work:work),type:"audio",expectedBytes:100,state:.failed)
        let job = VersionDownload(id:UUID(),work:work,version:version,created:.now,files:[first,second])
        #expect(!job.isComplete)
        #expect(job.finishedCount == 1)
    }

    @Test func cancellationRejectsLateCompletionAndRetryQueuesAgain() async throws {
        let dir = folder(); defer { try? FileManager.default.removeItem(at:dir) }
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let attempt = UUID()
        let file = DownloadFile(id:UUID(),track:PlaylistTrack(entry:try entry("01.mp3"),work:work),type:"audio",expectedBytes:100,attemptID:attempt,state:.downloading)
        let job = VersionDownload(id:UUID(),work:work,version:version,created:.now,files:[file])
        try JSONEncoder().encode([job]).write(to:dir.appendingPathComponent("index.json"))
        let store = VersionDownloadStore(directory:dir)
        store.pause(job.id)
        let incoming = dir.appendingPathComponent("late")
        try Data(repeating:1,count:100).write(to:incoming)
        await store.handle(.finished(attempt,incoming,100))
        #expect(!FileManager.default.fileExists(atPath:incoming.path))
        #expect(store.downloads[0].files[0].state == .queued)
        #expect(!store.hasCompleteVersion(work.id))
        store.retry(job.id)
        #expect(!store.downloads[0].paused)
    }

    @Test func realAudioCommitIsPlayableAndRestoresOffline() async throws {
        let dir = folder(); defer { try? FileManager.default.removeItem(at:dir) }
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        // A one-second, mono PCM WAV; no network or bundled media fixture needed.
        var wav = Data()
        func text(_ value: String) { wav.append(contentsOf:value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) { var value = value.littleEndian; withUnsafeBytes(of:&value) { wav.append(contentsOf:$0) } }
        text("RIFF"); number(UInt32(16036)); text("WAVEfmt "); number(UInt32(16))
        number(UInt16(1)); number(UInt16(1)); number(UInt32(8000)); number(UInt32(16000))
        number(UInt16(2)); number(UInt16(16)); text("data"); number(UInt32(16000)); wav.append(Data(repeating:0,count:16000))
        let attempt = UUID()
        let file = DownloadFile(id:UUID(),track:PlaylistTrack(entry:try entry("01.wav"),work:work),type:"audio",expectedBytes:Int64(wav.count),attemptID:attempt,state:.downloading)
        let job = VersionDownload(id:UUID(),work:work,version:version,created:.now,files:[file])
        try JSONEncoder().encode([job]).write(to:dir.appendingPathComponent("index.json"))
        let store = VersionDownloadStore(directory:dir)
        let incoming = dir.appendingPathComponent(attempt.uuidString)
        try wav.write(to:incoming)
        await store.handle(.finished(attempt,incoming,Int64(wav.count)))
        #expect(store.hasCompleteVersion(work.id))
        #expect(!FileManager.default.fileExists(atPath:incoming.path))
        let restored = VersionDownloadStore(directory:dir)
        let local = try #require(restored.localEntries(workID:work.id).first)
        #expect(local.node.streamURL?.isFileURL == true)
        #expect(try Data(contentsOf:try #require(local.node.streamURL)) == wav)
    }

    @Test func cacheConversionRequiresOriginalAndSurvivesCacheClear() async throws {
        let dir = folder(); defer { try? FileManager.default.removeItem(at:dir) }
        let defaults = UserDefaults(suiteName:UUID().uuidString)!
        let cache = AudioPlaybackCache(directory:dir,defaults:defaults,capacityOverride:1000)
        let source = dir.appendingPathComponent("source")
        try Data(repeating:1,count:100).write(to:source)
        let track = PlaylistTrack(entry:try entry("01.mp3"),work:work)
        let targetDir = folder(); defer { try? FileManager.default.removeItem(at:targetDir) }
        let target = targetDir.appendingPathComponent("export.mp3")
        try cache.commit(source,key:"01.mp3",bytes:100,fileExtension:"mp3")
        #expect(try await cache.exportOriginal(for:track,expectedBytes:100,to:target) == nil)
        try cache.commit(source,key:"01.mp3",bytes:100,fileExtension:"mp3",original:true)
        #expect(try await cache.exportOriginal(for:track,expectedBytes:101,to:target) == nil)
        #expect(try await cache.exportOriginal(for:track,expectedBytes:100,to:target) == target)
        cache.clear()
        #expect(try Data(contentsOf:target).count == 100)
        #expect(cache.file(for:"01.mp3") == nil)
    }
}
