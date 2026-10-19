import Foundation
import Testing
@testable import NeoSound

struct AttachmentTests {
    private func entry(_ name: String, type: String = "audio", path: String = "") throws -> TrackEntry {
        let data = try JSONSerialization.data(withJSONObject:["title":name,"type":type,"mediaDownloadUrl":"https://example.com/file"])
        let node = try JSONDecoder().decode(ASMRNode.self,from:data)
        return TrackEntry(id:path + name,node:node,path:path)
    }

    @Test func matchesSubtitleAcrossFoldersAndFormats() throws {
        let audio = try entry("01 greeting.mp3",path:"MP3")
        let subtitle = try entry("01 greeting.mp3.vtt",type:"text",path:"字幕")
        #expect(SubtitleMatcher.match(audio,in:[audio,subtitle]) == subtitle)
    }

    @Test func doesNotReuseUnrelatedSubtitle() throws {
        let first = try entry("01 greeting.mp3")
        let second = try entry("02 farewell.mp3")
        let subtitle = try entry("01 greeting.srt",type:"text")
        #expect(SubtitleMatcher.match(second,in:[first,second,subtitle]) == nil)
    }

    @Test func prefersSiblingAndRejectsAmbiguousMatches() throws {
        let audio = try entry("track.mp3",path:"JP")
        let jp = try entry("track.vtt",type:"text",path:"JP")
        let cn = try entry("track.vtt",type:"text",path:"CN")
        #expect(SubtitleMatcher.match(audio,in:[audio,jp,cn]) == jp)
        let other = try entry("track.wav",path:"WAV")
        #expect(SubtitleMatcher.match(other,in:[audio,other,jp,cn]) == nil)
    }

    @Test func subtitleHighlightEndsDuringSilence() {
        let lyrics = LocalLyrics(lines:[LyricLine(id:0,time:1,text:"hello",end:3)],plainText:"")
        #expect(lyrics.activeLine(at:0) == nil)
        #expect(lyrics.activeLine(at:2) == 0)
        #expect(lyrics.activeLine(at:3) == nil)
    }

    @Test func decodesScriptEncodings() throws {
        #expect(DocumentText.decode(Data("说明".utf8)) == "说明")
        #expect(DocumentText.decode(try #require("台本".data(using:.utf16))) == "台本")
        #expect(DocumentText.decode(try #require("こんにちは".data(using:.shiftJIS))) == "こんにちは")
    }
}
