import SwiftUI

/// The account symbol in a circle, as NeoDizzy shows a platform without an avatar image;
/// ASMR.ONE accounts have no avatar, so signing in fills the symbol.
struct AccountAvatar: View {
    @Environment(ASMRStore.self) private var store
    var size: CGFloat = 32
    var body: some View {
        Image(systemName:store.loggedIn ? "person.crop.circle.fill" : "person.crop.circle")
            .resizable().scaledToFit()
            .foregroundStyle(.tint)
            .frame(width:size,height:size)
            .clipShape(.circle)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The top-right account button on each tab's root page; it opens settings, where the account lives.
    func accountToolbar() -> some View { modifier(AccountToolbar()) }
}
/// A plain system toolbar button, as NeoDizzy's settings button: it gets the bar's glass background.
private struct AccountToolbar: ViewModifier {
    @Environment(AppRouter.self) private var router
    @Environment(ASMRStore.self) private var store
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                Button("账号与设置",systemImage:store.loggedIn ? "person.crop.circle.fill" : "person.crop.circle") { router.showsSettings = true }
                    .accessibilityValue(store.loggedIn ? store.user?.name ?? "已登录" : "未登录")
                    .accessibilityHint("打开账号和设置")
            }
        }
    }
}

struct AccountView: View {
    @Environment(ASMRStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var name = ""
    @State private var password = ""
    @State private var passwordVisible = false
    @State private var error: String?
    var body: some View {
        Form {
            if store.loggedIn {
                Section {
                    VStack(spacing:8) {
                        AccountAvatar(size:72)
                        Text(store.user?.name ?? "已登录").font(.title2.weight(.bold))
                        Text("ASMR.ONE · \(store.client.baseURL.host ?? "")").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth:.infinity).padding(.vertical,8)
                }
                .listRowBackground(Color.clear)
                Section {
                    Button("退出登录",role:.destructive) {
                        do { try store.logout() } catch { self.error = error.localizedDescription }
                    }
                }
            } else {
                Section {
                    TextField("用户名",text:$name).textContentType(.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack {
                        Group {
                            if passwordVisible { TextField("密码",text:$password) } else { SecureField("密码",text:$password) }
                        }
                        .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit(login)
                        Button { passwordVisible.toggle() } label: { Image(systemName:passwordVisible ? "eye.slash":"eye") }
                            .buttonStyle(.borderless).accessibilityLabel(passwordVisible ? "隐藏密码":"显示密码")
                    }
                    if name != name.trimmingCharacters(in:.whitespacesAndNewlines) {
                        Text("用户名开头或结尾含空白，请核对是否与网站一致。").font(.footnote).foregroundStyle(.orange)
                    }
                } footer: {
                    Text("登录线路：\(store.client.baseURL.host ?? "")。密码只用于这次登录，令牌保存在本机钥匙串。")
                }
                .disabled(store.accountBusy)
                Section {
                    Button(store.accountBusy ? "正在登录…" : "登录",action:login)
                        .disabled(store.accountBusy || name.isEmpty || password.isEmpty)
                    Link("在网站注册账号",destination:URL(string:"https://asmr.one/")!)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("账号")
        .onDisappear { password = ""; passwordVisible = false }
        .onChange(of:scenePhase) { if scenePhase != .active { passwordVisible = false } }
    }
    private func login() {
        guard !store.accountBusy, !name.isEmpty, !password.isEmpty else { return }
        let submittedName = name, submittedPassword = password
        passwordVisible = false; error = nil
        Task {
            do { try await store.login(name:submittedName,password:submittedPassword); password = "" }
            catch { self.error = error.localizedDescription }
        }
    }
}
