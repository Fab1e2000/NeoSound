import SwiftUI

/// The signed-in user's initial in an accent circle, or a person symbol when signed out.
struct AccountAvatar: View {
    @Environment(ASMRStore.self) private var store
    var size: CGFloat = 32
    var body: some View {
        if store.loggedIn, let initial = store.user?.name?.trimmingCharacters(in:.whitespaces).first {
            Text(String(initial).uppercased())
                .font(.system(size:size * 0.45,weight:.semibold))
                .foregroundStyle(.white)
                .frame(width:size,height:size)
                .background(Color.accentColor,in:.circle)
        } else {
            Image(systemName:"person.crop.circle.fill")
                .resizable().scaledToFit().frame(width:size,height:size)
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// The top-right avatar on each tab's root page; it opens settings, where the account lives.
    func accountToolbar() -> some View { modifier(AccountToolbar()) }
}
private struct AccountToolbar: ViewModifier {
    @Environment(AppRouter.self) private var router
    @Environment(ASMRStore.self) private var store
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                Button { router.showsSettings = true } label: { AccountAvatar(size:30) }
                    .accessibilityLabel(store.loggedIn ? "账号与设置，\(store.user?.name ?? "已登录")" : "账号与设置，未登录")
            }
            .sharedBackgroundVisibility(.hidden)
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
                    HStack(spacing:14) {
                        AccountAvatar(size:56)
                        VStack(alignment:.leading,spacing:2) {
                            Text(store.user?.name ?? "已登录").font(.title3.weight(.semibold))
                            Text(store.client.baseURL.host ?? "").font(.footnote).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical,4)
                }
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
