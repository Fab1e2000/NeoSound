import Foundation
import Testing
@testable import NeoSound

@Suite("准入判断")
struct AdmissionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    let track = Track(id: "syn-track-a", itemId: "syn-item-a", revision: "rev-1", title: "细雨", durationMs: 1000)
    var item: CatalogItem {
        CatalogItem(id: "syn-item-a", namespace: "synthetic", title: "窗边细雨", creator: nil, category: .rain,
                    summary: "", revision: "rev-1", artwork: .rain, tracks: [track])
    }

    func entry(track: String = "syn-track-a", revision: String = "rev-1", decision: Decision = .approved) -> AllowlistEntry {
        AllowlistEntry(namespace: "synthetic", itemId: "syn-item-a", trackId: track, revision: revision,
                       decision: decision, policyVersion: "p1")
    }

    func service(_ entries: [AllowlistEntry], revoked: Set<String> = [], validFor: TimeInterval = 3600) -> AdmissionService {
        let list = Allowlist(version: 7, generatedAt: now.addingTimeInterval(-60), validUntil: now.addingTimeInterval(validFor),
                             entries: entries, revokedTrackIds: revoked)
        let fixed = now
        return AdmissionService(allowlist: list, now: { fixed })
    }

    @Test func approvedTrackIsAdmitted() {
        #expect(service([entry()]).isPlayable(track, in: item))
    }

    @Test func missingAllowlistDenies() {
        #expect(AdmissionService(allowlist: nil).evaluate(track, in: item).failure == .allowlistMissing)
    }

    @Test("A01 只有关键词、没有审核记录 → 拒绝")
    func unlistedTrackIsDenied() {
        #expect(service([]).evaluate(track, in: item).failure == .notListed)
    }

    @Test("A02 作品下的新音轨不继承作品结论")
    func newTrackDoesNotInherit() {
        let newTrack = Track(id: "syn-track-new", itemId: "syn-item-a", revision: "rev-1", title: "新音轨", durationMs: nil)
        #expect(service([entry()]).evaluate(newTrack, in: item).failure == .notListed)
    }

    @Test("A03 同 ID 换了 revision → 旧审核失效")
    func revisionChangeInvalidates() {
        #expect(service([entry(revision: "rev-0")]).evaluate(track, in: item).failure == .revisionMismatch)
    }

    @Test("A04 白名单过期 → 拒绝")
    func expiredAllowlistDenies() {
        #expect(service([entry()], validFor: -1).evaluate(track, in: item).failure == .allowlistExpired)
    }

    @Test("D03 未知决策值 → 拒绝", arguments: [Decision.pendingReview, .rejected, .revoked, .unknown("approved_maybe")])
    func nonApprovedDecisionsDeny(decision: Decision) {
        #expect(service([entry(decision: decision)]).evaluate(track, in: item).failure == .notApproved(decision))
    }

    @Test("A06 撤销优先于 approved")
    func revocationWins() {
        #expect(service([entry()], revoked: ["syn-track-a"]).evaluate(track, in: item).failure == .revoked)
    }

    @Test func trackFromAnotherItemIsDenied() {
        let foreign = Track(id: "syn-track-a", itemId: "syn-item-b", revision: "rev-1", title: "x", durationMs: 1)
        #expect(service([entry()]).evaluate(foreign, in: item).failure == .notListed)
    }

    @Test func unknownDecisionStringDecodesAsUnknown() throws {
        let json = #"{"source_namespace":"synthetic","item_id":"a","track_id":"b","revision":"r","decision":"maybe_ok","policy_version":"p"}"#
        let decoded = try JSONDecoder().decode(AllowlistEntry.self, from: Data(json.utf8))
        #expect(decoded.decision == .unknown("maybe_ok"))
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
