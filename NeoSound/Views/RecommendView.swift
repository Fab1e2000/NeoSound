import SwiftUI

/// The recommend tab: the site's picks for the signed-in account, laid out like the browse grid.
/// Signed out, it shows the site's popular works and an invitation to sign in.
struct RecommendView: View {
    @Environment(ASMRStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var feed = WorkFeed()
    @State private var paginationVisible = false
    @State private var loadedID: String?
    private var uuid: String? { store.loggedIn ? store.user?.recommenderUuid : nil }
    private var requestID: String { "\(uuid ?? "popular")|\(store.client.baseURL.absoluteString)" }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                if !store.loggedIn { signInCard }
                Text(uuid == nil ? "热门作品" : "为你推荐").font(.title3.bold()).padding(.horizontal,4)
                WorkGrid(works:feed.works,loading:feed.loading)
                if feed.loading && !feed.works.isEmpty { ProgressView().frame(maxWidth:.infinity) }
                if let error = feed.error { RetryRow(message:error) { Task { await load(reset:feed.page == 0) } } }
                if !feed.loading && feed.works.isEmpty && feed.error == nil && !feed.hasNext {
                    ContentUnavailableView("暂无推荐",systemImage:"sparkles",description:Text("多听几部作品、在网站上打分后，推荐会更准确。"))
                }
                if feed.hasNext && feed.error == nil && feed.pausedOnFilteredPages && !feed.loading {
                    Button("继续查找更多作品") { Task { await load(reset:false) } }.frame(maxWidth:.infinity).padding(.vertical,8)
                } else if feed.hasNext && feed.error == nil {
                    Color.clear.frame(height:1)
                        .onScrollVisibilityChange(threshold:0.1) { paginationVisible = $0 }
                        .onChange(of:paginationVisible) { loadMoreIfVisible() }
                        .onChange(of:feed.page) { loadMoreIfVisible() }
                        .accessibilityHidden(true)
                }
            }.padding(12)
        }
        .navigationTitle("推荐")
        .navigationBarTitleDisplayMode(.large)
        .background(Color(.systemGroupedBackground))
        .accountToolbar()
        .refreshable { await load(reset:true) }
        .task(id:requestID) {
            // .task reruns when the page reappears; keep what is already loaded for the same account.
            if loadedID == requestID && feed.page > 0 { return }
            feed.clear(); await load(reset:true)
            if feed.page > 0 { loadedID = requestID }
        }
    }
    private var signInCard: some View {
        HStack(spacing:14) {
            Image(systemName:"sparkles").font(.title2).foregroundStyle(.tint)
                .frame(width:44,height:44).background(.tint.opacity(0.14),in:.circle)
                .accessibilityHidden(true)
            VStack(alignment:.leading,spacing:2) {
                Text("登录后查看为你推荐").font(.headline)
                Text("根据你在 ASMR.ONE 的收听和评分推荐作品。").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength:0)
            Button("登录") { router.showsSettings = true }.buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground),in:.rect(cornerRadius:22))
    }
    private func loadMoreIfVisible() {
        guard paginationVisible, !feed.loading, feed.hasNext, feed.error == nil else { return }
        Task { await load(reset:false,automatically:true) }
    }
    private func load(reset: Bool, automatically: Bool = false) async {
        let client = store.client, uuid = uuid
        await feed.load(reset:reset,automatically:automatically) { page in
            if let uuid { try await client.recommended(uuid:uuid,page:page) } else { try await client.popular(page:page) }
        }
    }
}
