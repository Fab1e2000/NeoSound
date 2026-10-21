import SwiftUI

/// Settings as a sheet from the account button.
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

/// Account on top, then what is shown, translation, appearance, network, library and about.
struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("translatesTitles") private var translatesTitles = true
    @AppStorage("showsSourceID") private var showsSourceID = false
    @AppStorage(ContentFilter.storageKey) private var allowsAdult = false
    @Environment(ASMRStore.self) private var store
    @Environment(TitleTranslator.self) private var translator
    @State private var confirmsAdult = false
    var body: some View {
        List {
            Group {
                Section {
                    NavigationLink { AccountView() } label: { accountHeader }
                }
                Section {
                    Toggle(isOn:Binding(get:{ allowsAdult },set:{ if $0 { confirmsAdult = true } else { allowsAdult = false } })) {
                        Label("显示 R18 作品",systemImage:"eye")
                    }
                    Toggle(isOn:$showsSourceID) { Label("卡片显示 RJ 号",systemImage:"number") }
                } header: { Text("内容") } footer: {
                    Text(allowsAdult ? "已启用 R18：浏览、搜索、推荐和标签都不做任何过滤。" : "默认只显示全年龄与 R15 作品，18 禁作品由服务器排除。")
                }
                Section {
                    Toggle(isOn:$translatesTitles) { Label("标题翻译成中文",systemImage:"character.bubble") }
                    NavigationLink { DeepSeekKeyView() } label: {
                        LabeledContent {
                            Text(translator.hasKey ? "已保存" : "未设置")
                        } label: { Label("DeepSeek API Key",systemImage:"key") }
                    }
                } header: { Text("标题翻译") } footer: {
                    Text("日语标题由 DeepSeek 翻译成简体中文，译文缓存在本机。")
                }
                Section("外观") {
                    Picker(selection:$appearance) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    } label: { Label("显示模式",systemImage:"circle.lefthalf.filled") }
                }
                Section {
                    Picker(selection:Binding(get:{ store.client.baseURL.absoluteString },set:{ host in
                        do { try store.changeHost(host) } catch { store.report(error) }
                    })) {
                        ForEach(ASMRClient.hosts,id:\.self) { Text($0.replacingOccurrences(of:"https://",with:"")).tag($0) }
                    } label: { Label("API 线路",systemImage:"network") }
                } header: { Text("网络") } footer: {
                    Text(store.loggedIn ? "某条线路访问慢或失败时可以换一条。登录只在当前线路有效，切换后需要重新登录。" : "某条线路访问慢或失败时可以换一条，切换后列表会重新加载。")
                }
                LibraryBackupSection()
                Section("关于") {
                    LabeledContent {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    } label: { Label("版本",systemImage:"info.circle") }
                    Link(destination:URL(string:"https://asmr.one/")!) { Label("ASMR.ONE 网站",systemImage:"safari") }
                }
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
        }
        .navigationTitle("设置")
        .confirmationDialog("启用 R18？",isPresented:$confirmsAdult,titleVisibility:.visible) {
            Button("我已年满 18 岁，启用") { allowsAdult = true }
            Button("取消",role:.cancel) {}
        } message: {
            Text("启用后浏览、搜索、推荐和标签都不再过滤 18 禁内容。")
        }
    }
    /// A large account row at the top, as in the system Settings app.
    private var accountHeader: some View {
        HStack(spacing:14) {
            AccountAvatar(size:56)
            VStack(alignment:.leading,spacing:3) {
                Text(store.loggedIn ? store.user?.name ?? "ASMR.ONE" : "登录 ASMR.ONE").font(.title3.weight(.semibold))
                Text(store.loggedIn ? "ASMR.ONE · \(store.client.baseURL.host ?? "")" : "登录后可查看为你推荐")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical,6)
    }
}

/// Saves or removes the DeepSeek key used for title translation.
private struct DeepSeekKeyView: View {
    @Environment(ASMRStore.self) private var store
    @Environment(TitleTranslator.self) private var translator
    @State private var apiKey = ""
    var body: some View {
        Form {
            Section {
                if translator.hasKey {
                    LabeledContent("DeepSeek API Key",value:"已保存")
                    Button("移除 API Key",role:.destructive) { save(nil) }
                } else {
                    SecureField("粘贴 DeepSeek API Key",text:$apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { save(apiKey) }
                    Button("保存") { save(apiKey) }.disabled(apiKey.trimmingCharacters(in:.whitespaces).isEmpty)
                }
                if let error = translator.lastError { Text(error).font(.footnote).foregroundStyle(.red) }
            } footer: {
                Text("日语标题由 DeepSeek（deepseek-flash）翻译，按 API 用量计费；译文缓存在本机，每个标题只翻译一次。Key 只存在本机 Keychain，只发送给 api.deepseek.com。")
            }
        }
        .navigationTitle("DeepSeek API Key")
        .navigationBarTitleDisplayMode(.inline)
    }
    private func save(_ key: String?) {
        do { try translator.setAPIKey(key); apiKey = "" } catch { store.report(error) }
    }
}
