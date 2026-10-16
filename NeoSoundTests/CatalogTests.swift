import Foundation
import Testing
@testable import NeoSound

@Suite("目录解码")
struct CatalogTests {
    func trackJSON(_ fields: String) -> Data {
        Data(#"{"track_id":"syn-t","item_id":"syn-i","title":"细雨","delivery":"progressive","subtitles":[]\#(fields)}"#.utf8)
    }

    @Test("D01 缺 revision → 解码失败")
    func missingRevisionFails() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Track.self, from: trackJSON(#","duration_ms":1000"#))
        }
    }

    @Test func emptyRevisionFails() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Track.self, from: trackJSON(#","revision":"","duration_ms":1000"#))
        }
    }

    @Test("D02 duration_ms 为 null → 时长未知")
    func nullDurationIsUnknown() throws {
        let track = try JSONDecoder().decode(Track.self, from: trackJSON(#","revision":"r","duration_ms":null"#))
        #expect(track.duration == nil)
        #expect(DurationFormat.label(track.duration) == "时长未知")
    }

    @Test("可空不等于可缺失")
    func missingDurationKeyFails() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Track.self, from: trackJSON(#","revision":"r""#))
        }
    }

    @Test func negativeDurationFails() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Track.self, from: trackJSON(#","revision":"r","duration_ms":-1"#))
        }
    }

    @Test("内置 Mock 目录与白名单可以载入，且准入结果符合预期")
    func bundledFixtures() {
        let library = Library(defaults: UserDefaults(suiteName: "CatalogTests")!)
        library.loadBundledFixtures()
        #expect(library.loadError == nil)
        #expect(library.items.count == 7)

        let rain = library.item(withId: "syn-item-rain")!
        #expect(library.isPlayable(rain.tracks[0], in: rain))
        #expect(!library.isPlayable(rain.tracks[1], in: rain))

        let storm = library.item(withId: "syn-item-storm")!
        #expect(library.evaluate(storm.tracks[0], in: storm).failure == .revisionMismatch)

        let homeIds = Set(library.recommended(category: nil).map(\.id))
        #expect(!homeIds.contains("syn-item-breath"))
        #expect(!homeIds.contains("syn-item-storm"))
        #expect(library.search("雨").map(\.id).contains("syn-item-storm"))
    }

    @Test func simulatedRevocationAndRestore() {
        let library = Library(defaults: UserDefaults(suiteName: "CatalogTests.revoke")!)
        library.loadBundledFixtures()
        let rain = library.item(withId: "syn-item-rain")!
        let before = library.allowlistRevision
        library.simulateRevocation(of: rain.tracks[0].id)
        #expect(library.allowlistRevision == before + 1)
        #expect(library.evaluate(rain.tracks[0], in: rain).failure == .revoked)
        library.restoreAllowlist()
        #expect(library.isPlayable(rain.tracks[0], in: rain))
    }

    @Test func durationFormatting() {
        #expect(DurationFormat.clock(724) == "12:04")
        #expect(DurationFormat.clock(3723) == "1:02:03")
        #expect(DurationFormat.label(1800) == "30 分钟")
        #expect(DurationFormat.label(5400) == "1.5 小时")
    }
}
