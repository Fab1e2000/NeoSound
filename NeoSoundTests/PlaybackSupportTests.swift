import AVFoundation
import Foundation
import Testing
@testable import NeoSound

@Suite("字幕与睡眠定时")
struct PlaybackSupportTests {
    @Test func parsesWebVTTAndStripsTags() {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:03.500
        <b>第一句</b>

        bad timing line
        nope

        01:00.000 --> 01:02.000 align:center
        第二句
        """
        let cues = WebVTT.parse(Data(vtt.utf8))
        #expect(cues.count == 2)
        #expect(cues[0].text == "第一句")
        #expect(cues[1].start == 60)
        #expect(WebVTT.activeCue(in: cues, at: 2)?.text == "第一句")
        #expect(WebVTT.activeCue(in: cues, at: 10) == nil)
    }

    @Test func rejectsNonVTT() {
        #expect(WebVTT.parse(Data("<html>login</html>".utf8)).isEmpty)
    }

    @Test func sleepFadeVolume() {
        #expect(SleepFade.volume(remaining: 120, fadeEnabled: true) == 1)
        #expect(SleepFade.volume(remaining: 15, fadeEnabled: true) == 0.5)
        #expect(SleepFade.volume(remaining: -3, fadeEnabled: true) == 0)
        #expect(SleepFade.volume(remaining: 5, fadeEnabled: false) == 1)
    }
}

nonisolated final class EmptyTracksProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("连续播放", .serialized)
@MainActor struct GaplessPlaybackTests {
    private func waitFor(sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for:.milliseconds(25))
        }
        try #require(condition(), sourceLocation:sourceLocation)
    }

    @Test func cacheClearKeepsBothPreparedFilesUntilReleased() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let cache = AudioPlaybackCache(directory:directory,defaults:UserDefaults(suiteName:UUID().uuidString)!)
        let source = directory.appendingPathComponent("source")
        try Data(repeating:1,count:100).write(to:source)
        try cache.commit(source,key:"current",bytes:100,fileExtension:"wav")
        try cache.commit(source,key:"next",bytes:100,fileExtension:"wav")
        let current = try #require(cache.file(for:"current")), next = try #require(cache.file(for:"next"))
        cache.protectFiles([current,next]); cache.clear()
        #expect(FileManager.default.fileExists(atPath:current.path))
        #expect(FileManager.default.fileExists(atPath:next.path))
        cache.protectFiles([next])
        #expect(!FileManager.default.fileExists(atPath:current.path))
        #expect(FileManager.default.fileExists(atPath:next.path))
        cache.protectFiles([])
        #expect(!FileManager.default.fileExists(atPath:next.path))
    }

    @Test func queueHandoffResetsLyricsAndHonorsSleepAndRepeat() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        var wav = Data()
        func text(_ value: String) { wav.append(contentsOf:value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) { var value = value.littleEndian; withUnsafeBytes(of:&value) { wav.append(contentsOf:$0) } }
        text("RIFF"); number(UInt32(16036)); text("WAVEfmt "); number(UInt32(16))
        number(UInt16(1)); number(UInt16(1)); number(UInt32(8000)); number(UInt32(16000))
        number(UInt16(2)); number(UInt16(16)); text("data"); number(UInt32(16000)); wav.append(Data(repeating:0,count:16000))
        let file = directory.appendingPathComponent("tone.wav"); try wav.write(to:file)
        let tracks = (0..<3).map { TrackEntry(id:"gapless-\($0)",node:ASMRNode(localURL:file,title:"\($0).wav",type:"audio",hash:nil,duration:1,size:nil),path:"") }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [EmptyTracksProtocol.self]
        let defaults = UserDefaults(suiteName:UUID().uuidString)!
        let store = ASMRStore(defaults:defaults,client:ASMRClient(session:URLSession(configuration:configuration)),readToken:{ nil },saveToken:{ _ in })
        let engine = AVQueuePlayer()
        let cache = AudioPlaybackCache(directory:directory.appendingPathComponent("cache"),defaults:defaults)
        let player = PlaybackCoordinator(store:store,cache:cache,player:engine)
        defer { player.stop() }
        let work = ASMRWork(id:987654321,title:"测试")
        player.play(tracks[0],in:work,tracks:tracks); player.pause()
        try await waitFor { engine.items().count == 2 }
        #expect(!player.hasSubtitles)
        let subtitle = directory.appendingPathComponent("0.vtt")
        try Data("WEBVTT\n\n00:00:00.000 --> 00:00:01.000\n歌词\n".utf8).write(to:subtitle)
        player.loadSubtitle(TrackEntry(id:"subtitle",node:ASMRNode(localURL:subtitle,title:"0.vtt",type:"text",hash:nil,duration:nil,size:nil),path:""))
        try await waitFor { player.hasSubtitles }
        let prepared = engine.items()[1]
        player.resume()
        try await waitFor { player.current?.id == tracks[1].id }
        player.pause()
        #expect(engine.currentItem === prepared)
        #expect(!player.hasSubtitles)
        #expect(player.subtitleLyrics == nil)
        player.setSleepTimer(.endOfTrack)
        #expect(engine.items().count == 1)
        #expect(engine.actionAtItemEnd == .pause)
        player.seek(to:0); player.resume()
        try await waitFor { player.phase == .ended }
        #expect(player.current?.id == tracks[1].id)
        player.setSleepTimer(.off)
        player.repeatMode = .one
        player.resume(); player.pause()
        try await waitFor { engine.items().count == 2 }
        let repeated = engine.items()[1]
        player.seek(to:0); player.resume()
        try await waitFor { engine.currentItem === repeated }
        player.pause()
        #expect(player.current?.id == tracks[1].id)
        player.repeatMode = .off
        player.playNext(tracks[0],in:work)
        try await waitFor { engine.items().count == 2 }
        player.next()
        #expect(player.current?.id == tracks[0].id)
        player.stop()
        #expect(engine.items().isEmpty)
    }
}
