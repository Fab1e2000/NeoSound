import SwiftUI

/// Settings' "资料库" section: import the backup, automatic backup, and a shareable export.
struct LibraryBackupSection: View {
    @Environment(LibraryBackup.self) private var backup
    var body: some View {
        Section {
            LibraryContextReader { LibraryImportButton(context:$0) }
            NavigationLink {
                LibraryBackupSettingsView()
            } label: {
                LabeledContent {
                    Text(backup.interval.title)
                } label: {
                    Label("自动备份",systemImage:"clock.arrow.circlepath")
                }
            }
            LibraryExportButton()
        } header: {
            Text("资料库")
        } footer: {
            Text("备份保存在「文件 › 我的 iPhone › NeoSound › Backup」。卸载 App 前把 Backup 文件夹复制出来，重装后放回原处，再点「导入备份」。")
        }
    }
}

/// Gathers the stores that export and import need from the environment.
struct LibraryContextReader<Content: View>: View {
    @Environment(FavoritesStore.self) private var favorites
    @Environment(LocalPlaylistStore.self) private var playlists
    @Environment(SearchHistory.self) private var history
    @Environment(TitleTranslator.self) private var translator
    @Environment(ASMRStore.self) private var store
    @ViewBuilder var content: (LibraryContext) -> Content
    var body: some View {
        content(LibraryContext(favorites:favorites,playlists:playlists,history:history,translator:translator,store:store))
    }
}

/// Scans the Backup folder and merges it in with one tap, no file picker (a re-signed app cannot open one).
private struct LibraryImportButton: View {
    let context: LibraryContext
    @Environment(LibraryBackup.self) private var backup
    @State private var result: ImportResult?
    @State private var failure: String?
    var body: some View {
        Button { restore() } label: { Label("导入备份",systemImage:"square.and.arrow.down") }
            .sheet(item:$result) { LibraryImportResultSheet(result:$0) }
            .alert("无法导入",isPresented:Binding(get:{ failure != nil },set:{ if !$0 { failure = nil } })) {
                Button("好") { failure = nil }
            } message: { Text(failure ?? "") }
    }
    private func restore() {
        do {
            let (export,url) = try backup.findBackup()
            let report = context.restore(export,includeSettings:true)
            // The old backup has been used; later automatic backups may overwrite it.
            backup.markBackedUp()
            result = ImportResult(fileName:url.lastPathComponent,exportedAt:export.exportedAt,report:report)
        } catch { failure = error.localizedDescription }
    }
}

private struct ImportResult: Identifiable {
    let id = UUID()
    let fileName: String
    let exportedAt: Date
    let report: LibraryRestoreReport
}

private struct LibraryImportResultSheet: View {
    let result: ImportResult
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("文件",value:result.fileName)
                    LabeledContent("备份时间",value:result.exportedAt.formatted(date:.abbreviated,time:.shortened))
                }
                Section {
                    ForEach(result.report.lines,id:\.self) { Text($0) }
                } footer: {
                    Text("导入只会添加，不会删除现有的收藏、列表和搜索记录。")
                }
            }
            .navigationTitle("已导入备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct LibraryBackupSettingsView: View {
    @Environment(LibraryBackup.self) private var backup
    @State private var confirmsOverwrite = false
    var body: some View {
        @Bindable var backup = backup
        LibraryContextReader { context in
            List {
                Section {
                    Picker("自动备份",selection:$backup.interval) {
                        ForEach(LibraryBackup.Interval.allCases) { Text($0.title).tag($0) }
                    }
                    LabeledContent("位置",value:"NeoSound › Backup")
                    if let last = backup.lastBackup {
                        LabeledContent("上次备份",value:last.formatted(date:.abbreviated,time:.shortened))
                    }
                    if backup.hasUnimportedBackup {
                        Text("Backup 里有一份之前留下的备份。为免被覆盖，导入它或手动「立即备份」之前不会自动备份。")
                            .foregroundStyle(.secondary)
                    }
                    if let error = backup.lastError { Text(error).foregroundStyle(.red) }
                } footer: {
                    Text("到期后，App 打开或进入后台时覆盖 Backup 里的备份文件。")
                }
                Section {
                    Toggle("备份 DeepSeek API Key",isOn:$backup.includesAPIKey)
                } footer: {
                    Text("重装后导入备份即可免重新填写。拿到这个备份文件的人也能用你的 Key 计费，请勿分享。")
                }
                Section {
                    Button(backup.isRunning ? "正在备份…" : "立即备份") {
                        if backup.hasUnimportedBackup { confirmsOverwrite = true } else { backup.backup(context) }
                    }
                    .disabled(backup.isRunning)
                }
            }
            .navigationTitle("自动备份")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("覆盖之前的备份？",isPresented:$confirmsOverwrite,titleVisibility:.visible) {
                Button("覆盖",role:.destructive) { backup.backup(context) }
                Button("取消",role:.cancel) {}
            } message: {
                Text("Backup 里的备份还没导入，覆盖后无法恢复其中的内容。")
            }
        }
    }
}

/// Exports a shareable library file (without the API key) through the share sheet.
struct LibraryExportButton: View {
    @State private var presented = false
    var body: some View {
        Button("导出资料库",systemImage:"square.and.arrow.up") { presented = true }
            .sheet(isPresented:$presented) { LibraryContextReader { LibraryExportSheet(context:$0) } }
    }
}

private struct LibraryExportSheet: View {
    let context: LibraryContext
    @Environment(\.dismiss) private var dismiss
    @State private var file: URL?
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("导出收藏的作品、我的列表、搜索记录、标题译文，以及外观、翻译、API 线路等设置。")
                    Text("文件不包含音频或 DeepSeek API Key，可以分享。换签名重装请用「导入备份」。")
                        .foregroundStyle(.secondary)
                }
                Section {
                    if let failure { Text(failure).foregroundStyle(.red) }
                    if let file {
                        ShareLink(item:file) { Label("分享资料库文件",systemImage:"square.and.arrow.up") }
                    } else if failure == nil {
                        ProgressView("正在准备文件")
                    }
                }
            }
            .navigationTitle("导出资料库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("完成") { dismiss() } } }
            .task { prepare() }
        }
    }
    private func prepare() {
        do {
            let name = "NeoSound-资料库-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
            let url = URL.temporaryDirectory.appending(path:name)
            try context.snapshot().data().write(to:url,options:.atomic)
            file = url
        } catch { failure = "导出失败：\(error.localizedDescription)" }
    }
}

/// Runs a due automatic backup when the app opens or moves to the background.
struct LibraryAutoBackup: View {
    @Environment(LibraryBackup.self) private var backup
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        LibraryContextReader { context in
            Color.clear
                .onChange(of:scenePhase,initial:true) { if scenePhase != .inactive { backup.runIfDue(context) } }
                .accessibilityHidden(true)
        }
    }
}
