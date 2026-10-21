import SwiftUI

/// Settings as a sheet from the avatar.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            SettingsView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button(role:.close) { dismiss() } } }
        }
    }
}

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("translatesTitles") private var translatesTitles = true
    @AppStorage("showsSourceID") private var showsSourceID = false
    @Environment(ASMRStore.self) private var store
    @Environment(TitleTranslator.self) private var translator
    @State private var apiKey = ""
    var body: some View {
        List {
            Group {
                Section("账号") {
                    // As NeoDizzy's account rows: symbol, name, then the sign-in state.
                    NavigationLink { AccountView() } label: {
                        HStack(spacing:12) {
                            AccountAvatar(size:32)
                            Text(store.loggedIn ? store.user?.name ?? "ASMR.ONE" : "ASMR.ONE")
                            Spacer()
                            Text(store.loggedIn ? "已登录" : "登录").foregroundStyle(.secondary)
                        }
                    }
                }
                Section("外观") {
                    Picker(selection:$appearance) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    } label: { Label("显示模式",systemImage:"circle.lefthalf.filled") }
                }
                Section("浏览") {
                    Toggle(isOn:$translatesTitles) { Label("标题翻译成中文",systemImage:"character.bubble") }
                    Toggle(isOn:$showsSourceID) { Label("卡片显示 RJ 号",systemImage:"number") }
                }
                Section {
                    if translator.hasKey {
                        LabeledContent("DeepSeek API Key",value:"已保存")
                        Button("移除 API Key",role:.destructive) { saveKey(nil) }
                    } else {
                        SecureField("粘贴 DeepSeek API Key",text:$apiKey)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onSubmit { saveKey(apiKey) }
                        Button("保存") { saveKey(apiKey) }.disabled(apiKey.trimmingCharacters(in:.whitespaces).isEmpty)
                    }
                    if let error = translator.lastError { Text(error).font(.footnote).foregroundStyle(.red) }
                } header: { Text("标题翻译") } footer: {
                    Text("日语标题由 DeepSeek（deepseek-flash）翻译，按 API 用量计费；译文缓存在本机，每个标题只翻译一次。Key 只存在本机 Keychain，只发送给 api.deepseek.com。")
                }
                Section("API 线路") {
                    Picker(selection:Binding(get:{store.client.baseURL.absoluteString},set:{ host in
                        do { try store.changeHost(host) } catch { store.report(error) }
                    })) {
                        ForEach(ASMRClient.hosts,id:\.self) { Text($0.replacingOccurrences(of:"https://",with:"")).tag($0) }
                    } label: { Label("线路",systemImage:"network") }
                    Text(store.loggedIn ? "某条线路访问慢或失败时可以换一条。登录只在当前线路有效，切换后需要重新登录。" : "某条线路访问慢或失败时可以换一条，切换后列表会重新加载。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                LibraryBackupSection()
                Section("关于") {
                    LabeledContent("版本",value:Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    Link("ASMR.ONE 网站",destination:URL(string:"https://asmr.one/")!)
                }
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
        }.navigationTitle("设置")
    }
    private func saveKey(_ key: String?) {
        do { try translator.setAPIKey(key); apiKey = "" } catch { store.report(error) }
    }
}
