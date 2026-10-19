import Foundation
import Testing
@testable import NeoSound

struct LibraryTests {
    private func work(_ id: Int) throws -> ASMRWork {
        try JSONDecoder().decode(ASMRWork.self,from:JSONSerialization.data(withJSONObject:["id":id,"title":"作品 \(id)"]))
    }
    private func entry(_ name: String, id: String, hash: String?, path: String = "MP3") throws -> TrackEntry {
        var object: [String: Any] = ["title":name,"type":"audio","mediaStreamUrl":"https://example.com/\(name)","duration":60]
        if let hash { object["hash"] = hash }
        let node = try JSONDecoder().decode(ASMRNode.self,from:JSONSerialization.data(withJSONObject:object))
        return TrackEntry(id:id,node:node,path:path)
    }
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path:"library-\(UUID().uuidString).json")
    }

    @Test func togglesAndPersistsFavoriteWorks() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at:url) }
        let store = FavoritesStore(fileURL:url)
        let first = try work(1)
        store.toggle(first); store.toggle(try work(2))
        #expect(FavoritesStore(fileURL:url).works.map(\.id) == [2,1])
        store.toggle(first)
        #expect(FavoritesStore(fileURL:url).works.map(\.id) == [2])
    }

    @Test func playlistsHoldTracksFromSeveralWorks() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at:url) }
        let store = LocalPlaylistStore(fileURL:url)
        let list = store.create(name:"睡前")
        let a = try entry("01.mp3",id:"1:/0/0:a",hash:"a"), b = try entry("03.mp3",id:"2:/0/2:b",hash:"b")
        store.toggle(a,of:try work(1),in:list.id); store.toggle(b,of:try work(2),in:list.id)
        store.move(from:[1],to:0,in:list.id)

        let reloaded = LocalPlaylistStore(fileURL:url)
        #expect(reloaded.playlists.first?.tracks.map(\.work.id) == [2,1])
        #expect(reloaded.contains(a,in:list.id))
        #expect(PlaylistSummary.text(reloaded.playlists[0].tracks) == "2 首 · " + DurationFormat.label(120))

        reloaded.toggle(a,of:try work(1),in:list.id)
        #expect(LocalPlaylistStore(fileURL:url).playlists.first?.tracks.map(\.id) == [b.id])
    }

    @Test func resolvesTrackAfterFileTreeChanges() throws {
        let original = try entry("01.mp3",id:"1:/0/0:abc",hash:"abc")
        let saved = PlaylistTrack(entry:original,work:try work(1))
        let moved = try entry("01.mp3",id:"1:/1/0:abc",hash:"abc")
        let rehashed = try entry("01.mp3",id:"1:/2/0:new",hash:"new")
        let other = try entry("02.mp3",id:"1:/0/1:def",hash:"def")
        #expect(saved.resolve(in:[other,original])?.id == original.id)
        #expect(saved.resolve(in:[other,moved])?.id == moved.id)
        #expect(saved.resolve(in:[other,rehashed])?.id == rehashed.id)
        #expect(saved.resolve(in:[other]) == nil)
    }
}
