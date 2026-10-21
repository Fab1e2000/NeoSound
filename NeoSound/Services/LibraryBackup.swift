import Foundation
import Observation

/// Portable library file: favorites, playlists, search history, title translations and settings.
/// Only the backup kept in the app's own folder may carry the DeepSeek API key; shared exports never do.
struct LibraryExport: Codable {
    static let formatName = "NeoSoundLibrary"
    var format = Self.formatName
    var version = 1
    let exportedAt: Date
    /// Newest first, as in the favorites grid.
    var favorites: [ASMRWork]
    var playlists: [LocalPlaylist]
    var searchHistory: [SearchEntry]
    /// Cleaned Japanese title → Chinese translation; translating them again would cost API credit.
    var translations: [String: String]
    var settings: Settings?
    var credentials: Credentials?

    /// All optional: a setting missing from the file, or removed in a later version, leaves the current one alone.
    struct Settings: Codable, Equatable {
        var appearance: String?
        var translatesTitles: Bool?
        var showsSourceID: Bool?
        var apiHost: String?
        var favoritesNewestFirst: Bool?
        var allTagsSortsByName: Bool?
        var lyricsFocusPosition: Double?
    }
    struct Credentials: Codable, Equatable {
        var deepSeekAPIKey: String?
    }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    static func decode(_ data: Data) throws -> LibraryExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let export = try? decoder.decode(LibraryExport.self, from: data), export.format == formatName else {
            throw ImportError.notLibraryFile
        }
        guard export.version <= 1 else { throw ImportError.newerVersion }
        return export
    }
    enum ImportError: LocalizedError {
        case notLibraryFile, newerVersion
        var errorDescription: String? {
            switch self {
            case .notLibraryFile: "这不是 NeoSound 导出的资料库文件。"
            case .newerVersion: "这个文件来自更新版本的 NeoSound，请先更新 App。"
            }
        }
    }
}

/// The stores and settings that export, import and automatic backup read and write.
struct LibraryContext {
    let favorites: FavoritesStore
    let playlists: LocalPlaylistStore
    let history: SearchHistory
    let translator: TitleTranslator
    let store: ASMRStore
    var defaults: UserDefaults = .standard

    func snapshot(includingAPIKey: Bool = false) -> LibraryExport {
        var export = LibraryExport(exportedAt:.now,favorites:favorites.works,playlists:playlists.playlists,
                                   searchHistory:history.entries,translations:translator.translations,settings:settings())
        if includingAPIKey, let key = translator.apiKey() { export.credentials = .init(deepSeekAPIKey:key) }
        return export
    }
    func settings() -> LibraryExport.Settings {
        LibraryExport.Settings(appearance:defaults.string(forKey:"appearance"),
                               translatesTitles:defaults.object(forKey:"translatesTitles") as? Bool,
                               showsSourceID:defaults.object(forKey:"showsSourceID") as? Bool,
                               apiHost:store.client.baseURL.absoluteString,
                               favoritesNewestFirst:defaults.object(forKey:"favoritesNewestFirst") as? Bool,
                               allTagsSortsByName:defaults.object(forKey:"allTagsSortsByName") as? Bool,
                               lyricsFocusPosition:defaults.object(forKey:"lyrics.focusPosition") as? Double)
    }
    /// Applies only the values written in the file; unrecognized ones keep the current setting.
    func apply(_ settings: LibraryExport.Settings) {
        if let appearance = settings.appearance, ["system","light","dark"].contains(appearance) { defaults.set(appearance,forKey:"appearance") }
        if let value = settings.translatesTitles { defaults.set(value,forKey:"translatesTitles") }
        if let value = settings.showsSourceID { defaults.set(value,forKey:"showsSourceID") }
        if let host = settings.apiHost { store.changeHost(host) }
        if let value = settings.favoritesNewestFirst { defaults.set(value,forKey:"favoritesNewestFirst") }
        if let value = settings.allTagsSortsByName { defaults.set(value,forKey:"allTagsSortsByName") }
        if let value = settings.lyricsFocusPosition { defaults.set(min(1,max(0,value)),forKey:"lyrics.focusPosition") }
    }
    /// Merges into what is here and never deletes anything.
    func restore(_ export: LibraryExport, includeSettings: Bool) -> LibraryRestoreReport {
        var report = LibraryRestoreReport()
        report.favoritesAdded = favorites.importWorks(export.favorites)
        (report.playlistsAdded,report.tracksAdded) = playlists.importPlaylists(export.playlists)
        history.importEntries(export.searchHistory)
        report.translationsAdded = translator.importTranslations(export.translations)
        if includeSettings, let settings = export.settings { apply(settings); report.settingsApplied = true }
        if let key = export.credentials?.deepSeekAPIKey, !key.isEmpty {
            if translator.hasKey { report.apiKey = .kept }
            else { report.apiKey = (try? translator.setAPIKey(key)) != nil ? .restored : .failed }
        }
        return report
    }
}

struct LibraryRestoreReport: Equatable {
    var favoritesAdded = 0
    var playlistsAdded = 0
    var tracksAdded = 0
    var translationsAdded = 0
    var settingsApplied = false
    var apiKey: APIKey?
    enum APIKey: Equatable { case restored, kept, failed }

    var lines: [String] {
        var lines = ["新增 \(favoritesAdded) 部收藏作品，\(playlistsAdded) 个列表，共 \(tracksAdded) 条音轨。"]
        if translationsAdded > 0 { lines.append("新增 \(translationsAdded) 条标题译文，不会再次计费翻译。") }
        if settingsApplied { lines.append("已恢复外观、标题翻译、API 线路等设置。") }
        switch apiKey {
        case .restored: lines.append("已恢复 DeepSeek API Key。")
        case .kept: lines.append("本机已有 DeepSeek API Key，保留当前的。")
        case .failed: lines.append("DeepSeek API Key 没能保存到钥匙串，请在设置里重新填写。")
        case nil: break
        }
        return lines
    }
}

/// The single library backup in "Files › On My iPhone › NeoSound › Backup".
/// A re-signed app cannot reach files outside its own folder, so the backup lives there:
/// copy the Backup folder out before uninstalling, put it back after reinstalling, then tap "导入备份".
@Observable
final class LibraryBackup {
    enum Interval: String, CaseIterable, Identifiable {
        case off, daily, weekly
        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: "关闭"
            case .daily: "每天"
            case .weekly: "每周"
            }
        }
        var seconds: TimeInterval? {
            switch self {
            case .off: nil
            case .daily: 24 * 3600
            case .weekly: 7 * 24 * 3600
            }
        }
    }

    static let fileName = "NeoSound-资料库.json"
    let folder: URL
    var fileURL: URL { folder.appending(path:Self.fileName) }
    var interval: Interval { didSet { defaults.set(interval.rawValue,forKey:Keys.interval) } }
    /// Puts the DeepSeek API key in the backup so a reinstall needs no re-entry.
    var includesAPIKey: Bool { didSet { defaults.set(includesAPIKey,forKey:Keys.apiKey) } }
    private(set) var lastBackup: Date?
    private(set) var lastError: String?
    private(set) var isRunning = false
    @ObservationIgnored private let defaults: UserDefaults
    private enum Keys {
        static let interval = "libraryBackup.interval"
        static let apiKey = "libraryBackup.includesAPIKey"
        static let last = "libraryBackup.lastBackup"
    }

    init(folder: URL = URL.documentsDirectory.appending(path:"Backup",directoryHint:.isDirectory), defaults: UserDefaults = .standard) {
        self.folder = folder; self.defaults = defaults
        interval = defaults.string(forKey:Keys.interval).flatMap(Interval.init(rawValue:)) ?? .daily
        includesAPIKey = defaults.object(forKey:Keys.apiKey) as? Bool ?? true
        lastBackup = defaults.object(forKey:Keys.last) as? Date
        // Created up front so the folder is easy to find in the Files app.
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    }

    /// A backup is in the folder but this install never wrote one: most likely an old backup just put back
    /// after reinstalling, which automatic backup must not overwrite before it is imported.
    var hasUnimportedBackup: Bool { lastBackup == nil && FileManager.default.fileExists(atPath:fileURL.path) }
    var isDue: Bool {
        guard let seconds = interval.seconds, !hasUnimportedBackup else { return false }
        return lastBackup.map { Date.now.timeIntervalSince($0) >= seconds } ?? true
    }
    func runIfDue(_ context: LibraryContext) {
        if isDue { backup(context) }
    }
    @discardableResult
    func backup(_ context: LibraryContext) -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        defer { isRunning = false }
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            try context.snapshot(includingAPIKey:includesAPIKey).data()
                .write(to:fileURL,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            lastError = nil
            markBackedUp()
            return true
        } catch {
            lastError = "备份失败：\(error.localizedDescription)"
            return false
        }
    }
    /// Once imported, the old file has served its purpose and automatic backup may overwrite it.
    func markBackedUp() {
        lastBackup = .now
        defaults.set(lastBackup,forKey:Keys.last)
    }
    /// The backup in the folder: the fixed file name first, else the newest NeoSound library file (e.g. renamed).
    func findBackup() throws -> (LibraryExport, URL) {
        if let data = try? Data(contentsOf:fileURL), let export = try? LibraryExport.decode(data) { return (export,fileURL) }
        let files = (try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.contentModificationDateKey])) ?? []
        let candidates = files.filter { $0.pathExtension.lowercased() == "json" }.sorted {
            let lhs = (try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs > rhs
        }
        for url in candidates {
            if let data = try? Data(contentsOf:url), let export = try? LibraryExport.decode(data) { return (export,url) }
        }
        throw BackupError.notFound
    }
    enum BackupError: LocalizedError {
        case notFound
        var errorDescription: String? {
            "没有找到备份。请把备份文件放进「文件 › 我的 iPhone › NeoSound › Backup」，再点「导入备份」。"
        }
    }
}
