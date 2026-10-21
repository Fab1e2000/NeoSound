import SwiftUI

/// Search text, presentation and the search tab's navigation; RootView activates search when the tab opens.
@Observable
final class SearchModel {
    var text = ""
    var isPresented = false
    var path = NavigationPath()
    var query: String { text.trimmingCharacters(in:.whitespacesAndNewlines) }
    func open(_ entry: SearchEntry, history: SearchHistory) {
        guard !entry.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        history.add(entry); path.append(entry.query)
    }
}

/// The search tab: recent searches and hot tags, then live suggestions while typing.
struct SearchTab: View {
    @Environment(ASMRStore.self) private var store
    @Environment(SearchHistory.self) private var history
    @Bindable var model: SearchModel
    @State private var hotTags = HotTags.allowed
    @State private var tagsLoaded = false
    var body: some View {
        NavigationStack(path:$model.path) {
            ScrollView {
                if model.query.isEmpty {
                    SearchHome(hotTags:Array(hotTags.prefix(16)),open:open)
                } else {
                    SearchSuggestions(text:model.query,open:open) { work in
                        history.add(.keyword(model.query)); model.path.append(work)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.large)
            .task {
                // Live counts only reorder the built-in list, so a failed request keeps the fallback silently.
                guard !tagsLoaded, let site = try? await store.client.tags() else { return }
                hotTags = HotTags.ranked(site); tagsLoaded = true
            }
            .navigationDestination(for:SearchRoute.self) { _ in AllTagsView(tags:hotTags,open:open) }
            .workDestinations()
        }
        // On the search tab's stack rather than the TabView, so the other tabs get no search field;
        // the system still places it in the tab bar for the search role.
        .searchable(text:$model.text,isPresented:$model.isPresented,prompt:"作品、标签、社团、声优")
        .onSubmit(of:.search) { open(.keyword(model.query)) }
    }
    private func open(_ entry: SearchEntry) { model.open(entry,history:history) }
}
enum SearchRoute: Hashable { case allTags }

private struct SearchHome: View {
    @Environment(SearchHistory.self) private var history
    let hotTags: [ASMRFacet]
    let open: (SearchEntry) -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:24) {
            if !history.entries.isEmpty {
                VStack(alignment:.leading,spacing:8) {
                    HStack {
                        Text("最近搜索").font(.title3.bold())
                        Spacer()
                        Button("清除") { withAnimation { history.clear() } }
                    }.padding(.horizontal,4)
                    VStack(spacing:0) {
                        ForEach(history.entries.prefix(10),id:\.self) { entry in
                            HStack(spacing:0) {
                                Button { open(entry) } label: {
                                    HStack(spacing:12) {
                                        Image(systemName:"clock").foregroundStyle(.secondary)
                                        Text(entry.name).lineLimit(1)
                                        if let label = entry.kindLabel { Text(label).font(.footnote).foregroundStyle(.secondary) }
                                        Spacer(minLength:0)
                                    }
                                    .frame(minHeight:46).contentShape(.rect)
                                }.buttonStyle(.plain)
                                Button { withAnimation { history.remove(entry) } } label: {
                                    Image(systemName:"xmark").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                                        .frame(width:44,height:44).contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("删除“\(entry.name)”")
                            }.padding(.leading,16).padding(.trailing,4)
                        }
                    }
                    .padding(.vertical,4)
                    .background(Color(.secondarySystemGroupedBackground),in:.rect(cornerRadius:22))
                }
            }
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    Text("热门标签").font(.title3.bold())
                    Spacer()
                    NavigationLink(value:SearchRoute.allTags) {
                        HStack(spacing:2) {
                            Text("全部")
                            Image(systemName:"chevron.right").font(.footnote.weight(.semibold))
                        }.font(.subheadline.weight(.medium))
                    }.accessibilityLabel("全部标签")
                }.padding(.horizontal,4)
                WorkChipLayout(spacing:8) {
                    ForEach(hotTags) { tag in
                        Button { open(SearchEntry(kind:.tag,name:tag.name)) } label: {
                            Text(tag.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                .padding(.horizontal,16).frame(minHeight:36)
                                .background(Color(.secondarySystemGroupedBackground),in:.capsule)
                                .contentShape(.capsule)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(16)
    }
}

/// Every all-ages tag, grouped, with work counts and a filter field.
private struct AllTagsView: View {
    let tags: [ASMRFacet]
    let open: (SearchEntry) -> Void
    @State private var filter = ""
    @AppStorage("allTagsSortsByName") private var sortsByName = false
    private var visible: [ASMRFacet] {
        let text = filter.trimmingCharacters(in:.whitespacesAndNewlines)
        let matched = text.isEmpty ? tags : tags.filter { $0.name.localizedStandardContains(text) }
        return sortsByName ? matched.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } : matched
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                HStack(spacing:6) {
                    Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
                    TextField("筛选 \(tags.count) 个标签",text:$filter).submitLabel(.done)
                    if !filter.isEmpty {
                        Button { filter = "" } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).accessibilityLabel("清空筛选")
                    }
                }
                .padding(.horizontal,10).frame(minHeight:40)
                .background(.fill.tertiary,in:.rect(cornerRadius:12))
                let groups = HotTags.grouped(visible)
                if groups.isEmpty { ContentUnavailableView.search(text:filter) }
                ForEach(groups,id:\.title) { group in
                    VStack(alignment:.leading,spacing:10) {
                        Text(group.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal,4)
                        WorkChipLayout(spacing:8) {
                            ForEach(group.tags) { tag in chip(tag) }
                        }
                    }
                }
            }.padding(16)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("全部标签")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                Menu {
                    Picker("排序",selection:$sortsByName) {
                        Label("按作品数",systemImage:"number").tag(false)
                        Label("按名称",systemImage:"textformat").tag(true)
                    }
                } label: { Label("排序",systemImage:"arrow.up.arrow.down") }
            }
        }
    }
    private func chip(_ tag: ASMRFacet) -> some View {
        Button { open(SearchEntry(kind:.tag,name:tag.name)) } label: {
            HStack(spacing:6) {
                Text(tag.name).font(.subheadline.weight(.medium))
                if let count = tag.count { Text(HotTags.countText(count)).font(.caption).foregroundStyle(.secondary) }
            }
            .lineLimit(1).padding(.horizontal,14).frame(minHeight:36)
            .background(Color(.secondarySystemGroupedBackground),in:.capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag.count.map { "\(tag.name)，\($0) 部作品" } ?? tag.name)
    }
}

private struct SearchSuggestions: View {
    @Environment(ASMRStore.self) private var store
    @Environment(SearchHistory.self) private var history
    @Environment(TitleTranslator.self) private var translator
    @AppStorage("translatesTitles") private var translatesTitles = true
    @State private var suggester = SearchSuggester()
    let text: String
    let open: (SearchEntry) -> Void
    let openWork: (ASMRWork) -> Void
    private struct Suggestion: Hashable {
        let entry: SearchEntry
        let systemImage: String
        let label: String
    }
    /// Matching recent searches first, then all-ages tags, then circles and voice actors from the live results.
    private var suggestions: [Suggestion] {
        let recent = history.entries.filter { $0.name.localizedStandardContains(text) && $0.name != text }.prefix(2)
            .map { Suggestion(entry:$0,systemImage:"clock",label:"最近搜索") }
        let tags = HotTags.allowed.filter { $0.name.localizedStandardContains(text) }.prefix(3)
            .map { Suggestion(entry:SearchEntry(kind:.tag,name:$0.name),systemImage:"tag",label:"标签") }
        let circles = suggester.circles.map { Suggestion(entry:SearchEntry(kind:.circle,name:$0),systemImage:"person.2",label:"社团") }
        let vas = suggester.vas.map { Suggestion(entry:SearchEntry(kind:.va,name:$0),systemImage:"person",label:"声优") }
        var seen = Set<SearchEntry>()
        return (recent + tags + circles + vas).filter { seen.insert($0.entry).inserted }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            VStack(spacing:0) {
                row(systemImage:"magnifyingglass",tint:.accentColor,title:"搜索“\(text)”的全部作品") { open(.keyword(text)) }
                ForEach(suggestions,id:\.self) { item in
                    row(systemImage:item.systemImage,tint:.secondary,title:item.entry.name,label:item.label) { open(item.entry) }
                }
            }
            .padding(.vertical,4)
            .background(Color(.secondarySystemGroupedBackground),in:.rect(cornerRadius:22))
            if !suggester.works.isEmpty {
                VStack(alignment:.leading,spacing:8) {
                    Text("作品").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal,4)
                    VStack(spacing:0) {
                        ForEach(suggester.works) { work in workRow(work) }
                    }
                    .padding(.vertical,6)
                    .background(Color(.secondarySystemGroupedBackground),in:.rect(cornerRadius:22))
                }
            } else if suggester.loading {
                ProgressView().frame(maxWidth:.infinity).padding()
            }
        }
        .padding(16)
        .task(id:text) { await suggester.update(text,client:store.client) }
    }
    private func row(systemImage: String, tint: Color, title: String, label: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            HStack(spacing:12) {
                Image(systemName:systemImage).foregroundStyle(tint).frame(width:22)
                Text(title).lineLimit(1)
                Spacer(minLength:8)
                if let label { Text(label).font(.footnote).foregroundStyle(.secondary) }
            }
            .padding(.horizontal,16).frame(minHeight:48).contentShape(.rect)
        }.buttonStyle(.plain)
    }
    private func workRow(_ work: ASMRWork) -> some View {
        Button { openWork(work) } label: {
            HStack(spacing:12) {
                WorkArtwork(work:work,radius:10).frame(width:52,height:52)
                VStack(alignment:.leading,spacing:2) {
                    Text(translator.display(work.title,translated:translatesTitles)).font(.body.weight(.medium)).lineLimit(1)
                    Text([work.creator,work.vas?.first.map { "CV " + $0.name }].compactMap { $0 }.joined(separator:" · "))
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength:0)
            }
            .padding(.horizontal,16).frame(minHeight:64).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .task(id:translatesTitles) { if translatesTitles { translator.request(work.title) } }
    }
}
