import Foundation
import Testing
@testable import NeoSound

@Suite("缓存", .serialized)
@MainActor struct CacheTests {
    private func folder() -> URL { FileManager.default.temporaryDirectory.appending(path:"audio-cache-\(UUID().uuidString)") }
    private func defaults() -> UserDefaults {
        let name = "cache-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:name)!
        defaults.removePersistentDomain(forName:name)
        return defaults
    }
    private func spool(_ bytes: Int, in directory: URL) throws -> URL {
        let url = directory.appending(path:UUID().uuidString + ".ready")
        try Data(repeating:7,count:bytes).write(to:url)
        return url
    }
    private func track(hash: String?, path: String = "MP3", title: String = "01.mp3") throws -> TrackEntry {
        var object: [String: Any] = ["title":title,"type":"audio","mediaStreamUrl":"https://example.com/\(title)"]
        if let hash { object["hash"] = hash }
        let node = try JSONDecoder().decode(ASMRNode.self,from:JSONSerialization.data(withJSONObject:object))
        return TrackEntry(id:"1:/0:\(title)",node:node,path:path)
    }

    @Test func keysFollowTheTrackAcrossFreshTrees() throws {
        #expect(AudioPlaybackCache.key(for:try track(hash:"1669833/1953384"),workID:1669833) == "1669833/1953384")
        #expect(AudioPlaybackCache.key(for:try track(hash:nil),workID:7) == "7|MP3|01.mp3")
        #expect(AudioPlaybackCache.mayContinue(listened:95,duration:100))
        #expect(!AudioPlaybackCache.mayContinue(listened:50,duration:100))
        #expect(!AudioPlaybackCache.mayContinue(listened:10,duration:0))
    }

    @Test func committedFilesSurviveRelaunchAndOldestGoFirst() throws {
        let directory = folder(), settings = defaults()
        defer { try? FileManager.default.removeItem(at:directory) }
        let cache = AudioPlaybackCache(directory:directory,defaults:settings,capacityOverride:250)
        try cache.commit(try spool(100,in:directory),key:"a",bytes:100,fileExtension:"mp3")
        try cache.commit(try spool(100,in:directory),key:"b",bytes:100,fileExtension:"mp3")
        #expect(cache.file(for:"a") != nil) // a is now the most recently used
        try cache.commit(try spool(100,in:directory),key:"c",bytes:100,fileExtension:"mp3")
        #expect(cache.file(for:"b") == nil)
        #expect(cache.bytes == 200)
        let relaunched = AudioPlaybackCache(directory:directory,defaults:settings,capacityOverride:250)
        #expect(relaunched.file(for:"a")?.pathExtension == "mp3" && relaunched.file(for:"c") != nil)
    }

    @Test func damagedFilesAndClearingLeaveNothingBehind() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at:directory) }
        let cache = AudioPlaybackCache(directory:directory,defaults:defaults(),capacityOverride:1_000)
        try cache.commit(try spool(100,in:directory),key:"a",bytes:100,fileExtension:"mp3")
        try cache.commit(try spool(100,in:directory),key:"b",bytes:100,fileExtension:"exe")
        #expect(cache.file(for:"b")?.pathExtension == "audio")
        try Data([1]).write(to:try #require(cache.file(for:"a")))
        #expect(cache.file(for:"a") == nil)
        #expect(throws:(any Error).self) { try cache.commit(try spool(10,in:directory),key:"c",bytes:99,fileExtension:"mp3") }
        cache.clear()
        #expect(cache.bytes == 0 && cache.file(for:"b") == nil)
    }

    @Test func turningTheCacheOffRefusesNewSpools() {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at:directory) }
        let cache = AudioPlaybackCache(directory:directory,defaults:defaults())
        cache.capacityGB = 0
        #expect(cache.makeItem(url:URL(string:"https://example.com/a.mp3")!,key:"a",expectedBytes:10) == nil)
        cache.capacityGB = 1
        #expect(cache.makeItem(url:URL(string:"https://example.com/a.mp3")!,key:"a",expectedBytes:2 * 1_024 * 1_024 * 1_024) == nil)
    }
}
