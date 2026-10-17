import SwiftUI

struct QueueView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var playback = playback
        NavigationStack {
            List {
                Section {
                    Picker("循环",selection:$playback.repeatMode) { Text("顺序播放").tag(0); Text("列表循环").tag(1); Text("单曲循环").tag(2) }
                    Button("打乱后续队列") { playback.shuffleRemaining() }
                }
                Section("\(playback.queue.count) 条音轨") {
                    ForEach(playback.queue) { entry in
                        Button { playback.selectQueue(entry) } label: {
                            HStack { Image(systemName:entry.id == playback.current?.id ? "waveform":"music.note"); Text(entry.track.title).foregroundStyle(.primary) }
                        }.swipeActions { if entry.id != playback.current?.id { Button("移除",role:.destructive) { playback.removeFromQueue(entry.id) } } }
                    }
                }
            }.navigationTitle("播放队列").toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
