import Foundation
import Testing
@testable import NeoSound

struct LibraryBackupTests {
    private func work(_ id: Int) throws -> ASMRWork {
        try JSONDecoder().decode(ASMRWork.self,from:JSONSerialization.data(withJSONObject:["id":id,"title":"作品 \(id)"]))
    }
    private func temporaryURL(_ name: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory.appending(path:"backup-\(name)")
    }
    private func defaults() -> UserDefaults {
        let name = "backup-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:name)!
        defaults.removePersistentDomain(forName:name)
        return defaults
    }
    private func context(key: String? = nil) -> LibraryContext {
        let store = ASMRStore(defaults:defaults())
        let translator = TitleTranslator(cacheURL:temporaryURL(),readKey:{ key })
        return LibraryContext(favorites:FavoritesStore(fileURL:temporaryURL()),playlists:LocalPlaylistStore(fileURL:temporaryURL()),
                              history:SearchHistory(defaults:defaults()),translator:translator,store:store,defaults:defaults())
    }

    @Test func exportRoundTripsAndRejectsOtherFiles() throws {
        let source = context()
        source.favorites.toggle(try work(1)); source.favorites.toggle(try work(2))
        source.playlists.create(name:"睡前")
        source.history.add(.keyword("雨声"))
        source.defaults.set("dark",forKey:"appearance")
        let data = try source.snapshot().data()
        let decoded = try LibraryExport.decode(data)
        #expect(decoded.favorites.map(\.id) == [2,1])
        #expect(decoded.playlists.map(\.name) == ["睡前"])
        #expect(decoded.searchHistory == [.keyword("雨声")])
        #expect(decoded.settings?.appearance == "dark")
        #expect(decoded.credentials == nil)
        #expect(throws:LibraryExport.ImportError.self) { try LibraryExport.decode(Data("{\"format\":\"Other\"}".utf8)) }
    }

    @Test func restoreMergesWithoutDeleting() throws {
        let source = context()
        source.favorites.toggle(try work(1)); source.favorites.toggle(try work(2))
        let list = source.playlists.create(name:"睡前")
        source.history.add(.keyword("雨声"))
        let export = source.snapshot()

        let target = context()
        target.favorites.toggle(try work(3)); target.favorites.toggle(try work(2))
        target.history.add(.keyword("耳语"))
        let report = target.restore(export,includeSettings:false)
        #expect(report.favoritesAdded == 1)
        #expect(target.favorites.works.map(\.id) == [2,3,1])
        #expect(target.playlists.playlists.map(\.id) == [list.id])
        #expect(target.history.entries == [.keyword("耳语"),.keyword("雨声")])
        #expect(target.restore(export,includeSettings:false).favoritesAdded == 0)
        #expect(target.playlists.playlists.count == 1)
    }

    @Test func onlyTheLocalBackupCarriesTheAPIKey() {
        let source = context(key:"sk-test")
        #expect(source.snapshot().credentials == nil)
        #expect(source.snapshot(includingAPIKey:true).credentials?.deepSeekAPIKey == "sk-test")
    }

    @Test func backupWritesOnceAndProtectsAnUnimportedFile() throws {
        let folder = temporaryURL()
        defer { try? FileManager.default.removeItem(at:folder) }
        let settings = defaults()
        let backup = LibraryBackup(folder:folder,defaults:settings)
        #expect(backup.isDue)
        #expect(backup.backup(context()))
        #expect(!backup.isDue)
        #expect(try backup.findBackup().1.lastPathComponent == LibraryBackup.fileName)

        // A fresh install that finds an old backup must not overwrite it automatically.
        let reinstalled = LibraryBackup(folder:folder,defaults:defaults())
        #expect(reinstalled.hasUnimportedBackup)
        #expect(!reinstalled.isDue)
    }
}
