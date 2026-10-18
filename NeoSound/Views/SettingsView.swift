import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("translatesTitles") private var translatesTitles = true
    @AppStorage("showsSourceID") private var showsSourceID = false
    @Environment(ASMRStore.self) private var store
    @Environment(TitleTranslator.self) private var translator
    @State private var apiKey = ""
    var body: some View {
        List {
            Section("外观") {
                Picker("显示模式",selection:$appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
            }
            Section("浏览") {
                Toggle("标题翻译成中文",isOn:$translatesTitles)
                Toggle("卡片显示 RJ 号",isOn:$showsSourceID)
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
                Picker("线路",selection:Binding(get:{store.client.baseURL.absoluteString},set:{ store.changeHost($0) })) {
                    ForEach(ASMRClient.hosts,id:\.self) { Text($0.replacingOccurrences(of:"https://",with:"")).tag($0) }
                }
                Text("某条线路访问慢或失败时可以换一条，切换后列表会重新加载。") .font(.footnote).foregroundStyle(.secondary)
            }
            Section("关于") {
                LabeledContent("版本",value:Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                Link("ASMR.ONE 网站",destination:URL(string:"https://asmr.one/")!)
            }
        }.navigationTitle("设置")
    }
    private func saveKey(_ key: String?) {
        do { try translator.setAPIKey(key); apiKey = "" } catch { store.report(error) }
    }
}
