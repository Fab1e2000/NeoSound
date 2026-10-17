import SwiftUI

struct WorkBrowser: View {
    @Environment(ASMRStore.self) private var store
    let title: String
    var keyword = ""
    @State private var feed = WorkFeed()
    @State private var paginationVisible = false
    @State private var sort: WorkSort = .create_date
    @State private var ascending = false
    @State private var subtitle = false
    @State private var seed = Int.random(in:0..<100)
    private var requestID: String { "\(keyword)|\(sort.rawValue)|\(ascending)|\(subtitle)|\(store.sessionRevision)" }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                HStack {
                    Text(feed.total > 0 ? "\(feed.total) 部作品" : "作品").foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Picker("排序",selection:$sort) { ForEach(WorkSort.allCases) { Text($0.title).tag($0) } }
                        Toggle("升序",isOn:$ascending)
                        Toggle("含字幕",isOn:$subtitle)
                    } label: { Label(sort.title,systemImage:subtitle ? "line.3.horizontal.decrease.circle.fill":"line.3.horizontal.decrease") }
                }.font(.subheadline)
                WorkGrid(works:feed.works,loading:feed.loading)
                if feed.loading && !feed.works.isEmpty { ProgressView().frame(maxWidth:.infinity) }
                if let error = feed.error { RetryRow(message:error) { Task { await load(reset:feed.page == 0) } } }
                if !feed.loading && feed.works.isEmpty && feed.error == nil { ContentUnavailableView("暂无作品",systemImage:"waveform",description:Text("试试其他关键词。")) }
                if feed.hasNext && feed.error == nil {
                    Color.clear.frame(height:1)
                        .onScrollVisibilityChange(threshold:0.1) { paginationVisible = $0 }
                        .onChange(of:paginationVisible) { loadMoreIfVisible() }
                        .onChange(of:feed.page) { loadMoreIfVisible() }
                        .accessibilityHidden(true)
                }
                if !feed.hasNext && !feed.loading && !feed.works.isEmpty && feed.error == nil {
                    Text("已显示全部作品").font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth:.infinity).padding(.vertical,8)
                }
            }.padding(12)
        }
        .navigationTitle(title)
        .background(Color(.systemGroupedBackground))
        .refreshable { seed = Int.random(in:0..<100); await load(reset:true) }
        .task(id:requestID) { feed.clear(); await load(reset:true) }
    }
    private func loadMoreIfVisible() {
        guard paginationVisible, !feed.loading, feed.hasNext, feed.error == nil else { return }
        // Keep the request alive when the loading indicator moves the trigger offscreen.
        Task { await load(reset:false,automatically:true) }
    }
    private func load(reset: Bool, automatically: Bool = false) async {
        let client = store.client, keyword = keyword, sort = sort, ascending = ascending, subtitle = subtitle, seed = seed
        await feed.load(reset:reset,automatically:automatically) { page in
            try await client.works(keyword:keyword,page:page,sort:sort,ascending:ascending,subtitle:subtitle,seed:seed)
        }
    }
}
struct WorkGrid: View {
    let works: [ASMRWork]
    var loading = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var columns: [GridItem] { dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(),spacing:8,alignment:.top),GridItem(.flexible(),spacing:8,alignment:.top)] }
    var body: some View {
        LazyVGrid(columns:columns,alignment:.leading,spacing:8) {
            ForEach(works) { work in ItemCard(item:work) }
            if loading && works.isEmpty {
                ForEach(0..<6,id:\.self) { _ in
                    VStack(alignment:.leading,spacing:8) {
                        RoundedRectangle(cornerRadius:12).fill(.quaternary).aspectRatio(4.0/3,contentMode:.fit)
                        RoundedRectangle(cornerRadius:4).fill(.quaternary).frame(height:14)
                        RoundedRectangle(cornerRadius:4).fill(.quaternary).frame(width:80,height:10)
                    }.accessibilityLabel("载入作品")
                }
            }
        }
    }
}
struct WorkArtwork: View {
    let work: ASMRWork
    var radius: CGFloat = 16
    var aspectRatio: CGFloat = 1
    var body: some View {
        Rectangle().fill(.quaternary).aspectRatio(aspectRatio,contentMode:.fit)
            .overlay {
                GeometryReader { geometry in
                    AsyncImage(url:work.coverURL) { image in image.resizable().scaledToFill() } placeholder: {
                        Image(systemName:"waveform").foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)
                    }.frame(width:geometry.size.width,height:geometry.size.height).clipped()
                }
            }.clipShape(.rect(cornerRadius:radius)).accessibilityHidden(true)
    }
}
struct ItemCard: View {
    let item: ASMRWork
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            NavigationLink(value:item) {
                WorkArtwork(work:item,radius:0,aspectRatio:4.0/3)
                    .fixedSize(horizontal:false,vertical:true)
                    .overlay(alignment:.topLeading) {
                        Text(item.sourceID).font(.caption2.weight(.medium)).padding(.horizontal,5).padding(.vertical,3)
                            .foregroundStyle(.white).background(.black.opacity(0.65),in:.rect(cornerRadius:4)).padding(5)
                    }
                    .overlay(alignment:.bottomTrailing) {
                        if let release = item.release {
                            Text(release).font(.caption2).padding(3).foregroundStyle(.white).background(.black.opacity(0.65))
                        }
                    }
            }.buttonStyle(.plain)
            Divider()
            VStack(alignment:.leading,spacing:6) {
                NavigationLink(value:item) {
                    Text(item.title).font(.subheadline.weight(.medium)).lineLimit(3,reservesSpace:true)
                        .frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(.primary)
                }.buttonStyle(.plain)
                WorkChipLayout(spacing:4) {
                    ForEach(item.tags ?? []) { tag in
                        chip(tag.name,namespace:"tag",color:.secondary)
                    }
                    if let circle = item.circle { chip(circle.name,namespace:"circle",color:.orange) }
                    ForEach(item.vas ?? []) { va in chip(va.name,namespace:"va",color:.green) }
                    if let duration = item.duration {
                        Label(DurationFormat.clock(duration),systemImage:"clock")
                            .font(.caption2).padding(.horizontal,6).padding(.vertical,3)
                            .background(.quaternary,in:Capsule())
                    }
                }
            }.padding(8)
        }
        .fixedSize(horizontal:false,vertical:true)
        .background(Color(.secondarySystemGroupedBackground),in:.rect(cornerRadius:12))
        .clipShape(.rect(cornerRadius:12))
    }
    private func chip(_ title: String, namespace: String, color: Color) -> some View {
        NavigationLink { WorkBrowser(title:title,keyword:"$\(namespace):\(title)$") } label: {
            Text(title).font(.caption2).lineLimit(1).padding(.horizontal,6).padding(.vertical,3)
                .foregroundStyle(color).background(color.opacity(0.12),in:Capsule())
        }.buttonStyle(.plain)
    }
}

/// Wrap the website's tag, circle and voice chips within the card's available width.
private struct WorkChipLayout: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width:proposal.width ?? 180,subviews:subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(width:bounds.width,subviews:subviews)
        for (index,point) in result.points.enumerated() {
            subviews[index].place(at:CGPoint(x:bounds.minX + point.x,y:bounds.minY + point.y),anchor:.topLeading,
                                  proposal:ProposedViewSize(width:result.widths[index],height:nil))
        }
    }
    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint], widths: [CGFloat]) {
        let width = max(1,width)
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var points: [CGPoint] = [], widths: [CGFloat] = []
        for view in subviews {
            let itemWidth = min(width,view.sizeThatFits(.unspecified).width)
            let size = view.sizeThatFits(ProposedViewSize(width:itemWidth,height:nil))
            if x > 0 && x + itemWidth > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x:x,y:y)); widths.append(itemWidth)
            x += itemWidth + spacing; rowHeight = max(rowHeight,size.height)
        }
        return (CGSize(width:width,height:y + rowHeight),points,widths)
    }
}
struct ItemRow: View {
    let item: ASMRWork
    var body: some View {
        HStack(spacing:12) {
            WorkArtwork(work:item,radius:10).frame(width:58,height:58)
            VStack(alignment:.leading,spacing:4) {
                Text(item.title).lineLimit(2)
                Text(item.creator ?? item.sourceID).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
struct RetryRow: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing:8) { Text(message).font(.footnote).foregroundStyle(.secondary); Button("重试",action:retry) }.frame(maxWidth:.infinity).padding()
    }
}
