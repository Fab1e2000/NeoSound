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

    @Test func bundledSubtitleParses() throws {
        let url = try #require(Bundle.main.url(forResource: "rain", withExtension: "vtt"))
        #expect(WebVTT.parse(try Data(contentsOf: url)).count >= 5)
    }

    @Test func sleepFadeVolume() {
        #expect(SleepFade.volume(remaining: 120, fadeEnabled: true) == 1)
        #expect(SleepFade.volume(remaining: 15, fadeEnabled: true) == 0.5)
        #expect(SleepFade.volume(remaining: -3, fadeEnabled: true) == 0)
        #expect(SleepFade.volume(remaining: 5, fadeEnabled: false) == 1)
    }
}
