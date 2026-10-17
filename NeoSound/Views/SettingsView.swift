import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("translatesTitles") private var translatesTitles = true
    @AppStorage("showsSourceID") private var showsSourceID = false
    @Environment(ASMRStore.self) private var store
    @Environment(PlaybackCoordinator.self) private var playback
    var body: some View {
        @Bindable var store = store
        List {
            Section("账号") {
                NavigationLink { AccountView() } label: {
                    Label(store.loggedIn ? store.user?.name ?? "ASMR.ONE 账号" : "登录 ASMR.ONE",systemImage:"person.crop.circle")
                }
            }
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
                Text("日语标题使用 Apple 设备端翻译模型，首次使用需下载日语→中文语言包。") .font(.footnote).foregroundStyle(.secondary)
            }
            Section("播放") {
                Toggle("优先流畅音质",isOn:$store.preferSmall)
                Text("下次切换音轨时生效；无低清版本时使用原始音频。") .font(.footnote).foregroundStyle(.secondary)
            }
            Section("API 线路") {
                Picker("线路",selection:Binding(get:{store.client.baseURL.absoluteString},set:{ host in
                    do { try store.changeHost(host); playback.stop() } catch { store.report(error) }
                })) {
                    ForEach(ASMRClient.hosts,id:\.self) { Text($0.replacingOccurrences(of:"https://",with:"")).tag($0) }
                }
                Text("切换线路将退出登录并停止播放，避免把令牌发送给不同来源。") .font(.footnote).foregroundStyle(.secondary)
            }
            Section("关于") {
                LabeledContent("版本",value:Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                Link("ASMR.ONE 网站",destination:URL(string:"https://asmr.one/")!)
            }
        }.navigationTitle("设置")
    }
}
struct AccountView: View {
    @Environment(ASMRStore.self) private var store
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var name = ""
    @State private var password = ""
    @State private var passwordVisible = false
    @State private var error: String?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Form {
            if store.loggedIn {
                LabeledContent("用户名",value:store.user?.name ?? "已登录")
                Button("退出登录",role:.destructive) {
                    do { try store.logout(); playback.stop() } catch { self.error = error.localizedDescription }
                }
            } else {
                Picker("登录线路",selection:Binding(get:{store.client.baseURL.absoluteString},set:{ host in
                    do { try store.changeHost(host); error = nil } catch { self.error = error.localizedDescription }
                })) {
                    ForEach(ASMRClient.hosts,id:\.self) { Text($0.replacingOccurrences(of:"https://",with:"")).tag($0) }
                }.disabled(store.accountBusy)
                TextField("用户名",text:$name).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(store.accountBusy)
                HStack {
                    Group {
                        if passwordVisible { TextField("密码",text:$password) }
                        else { SecureField("密码",text:$password) }
                    }
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(store.accountBusy)
                    Button {
                        passwordVisible.toggle()
                    } label: {
                        Image(systemName:passwordVisible ? "eye.slash":"eye")
                    }.buttonStyle(.borderless)
                        .accessibilityLabel(passwordVisible ? "隐藏密码":"显示密码")
                }
                if name != name.trimmingCharacters(in:.whitespacesAndNewlines) {
                    Text("用户名开头或结尾含空白，请核对是否与网站一致。")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Button(store.accountBusy ? "正在登录…":"登录") {
                    let submittedName = name
                    let submittedPassword = password
                    let submittedHost = store.client.baseURL.host ?? ""
                    passwordVisible = false
                    Task {
                        error = nil
                        do { try await store.login(name:submittedName,password:submittedPassword); password = "" }
                        catch { self.error = "\(error.localizedDescription)\n登录线路：\(submittedHost)" }
                    }
                }.disabled(store.accountBusy || name.isEmpty || password.isEmpty)
                Link("在网站注册账号",destination:URL(string:"https://asmr.one/")!)
                Text("密码只用于本次登录，令牌保存在设备 Keychain。") .font(.footnote).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("账号").onDisappear { password = ""; passwordVisible = false }
            .onChange(of:scenePhase) { _, phase in if phase != .active { passwordVisible = false } }
    }
}
