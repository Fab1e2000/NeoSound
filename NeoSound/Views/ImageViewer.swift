import SwiftUI

nonisolated struct ViewerImage: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let title: String
}

/// Full-screen image viewer: swipe between images, pinch or double-tap to zoom, drag while zoomed.
struct ImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let images: [ViewerImage]
    @State private var selection: String

    init(images: [ViewerImage], start: ViewerImage.ID? = nil) {
        self.images = images
        _selection = State(initialValue: start ?? images.first?.id ?? "")
    }

    private var current: ViewerImage? { images.first { $0.id == selection } }
    private var position: Int { (images.firstIndex { $0.id == selection } ?? 0) + 1 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(images) { image in
                    ZoomableImage(url: image.url).tag(image.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
                }
                .accessibilityLabel("关闭")
                VStack(spacing: 2) {
                    if let current { Text(current.title).font(.subheadline.weight(.semibold)).lineLimit(1) }
                    if images.count > 1 { Text("\(position) / \(images.count)").font(.caption).foregroundStyle(.white.opacity(0.7)) }
                }
                .frame(maxWidth: .infinity)
                if let current {
                    ShareLink(item: current.url) {
                        Image(systemName: "square.and.arrow.up").font(.headline).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("分享")
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .background(.black.opacity(0.35), in: .capsule)
            .padding(.horizontal, 12)
        }
        .statusBarHidden()
    }
}

private struct ZoomableImage: View {
    let url: URL
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnify)
                    // Dragging pans only while zoomed, so swiping still pages at normal size.
                    .gesture(pan, including: scale > 1 ? .all : .none)
                    .onTapGesture(count: 2) {
                        withAnimation(.snappy) {
                            if scale > 1 { reset() } else { scale = 2.5; lastScale = 2.5 }
                        }
                    }
            } else if phase.error != nil {
                ContentUnavailableView("图片载入失败", systemImage: "photo", description: Text("检查网络后左右滑动重试。"))
                    .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { scale = min(max(lastScale * $0.magnification, 1), 5) }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 { withAnimation(.snappy) { reset() } }
            }
    }
    private var pan: some Gesture {
        DragGesture()
            .onChanged { offset = CGSize(width: lastOffset.width + $0.translation.width, height: lastOffset.height + $0.translation.height) }
            .onEnded { _ in lastOffset = offset }
    }
    private func reset() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }
}
