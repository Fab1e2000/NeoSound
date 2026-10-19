import SwiftUI

struct SleepTimerSheet: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.dismiss) private var dismiss
    @State private var selection: SleepTimerMode = .off
    @State private var fadeOut = true

    private let options: [(SleepTimerMode, String)] = [
        (.off, "关闭"),
        (.minutes(15), "15 分钟"),
        (.minutes(30), "30 分钟"),
        (.minutes(45), "45 分钟"),
        (.minutes(60), "1 小时"),
        (.minutes(90), "1.5 小时"),
        (.endOfTrack, "播完本首"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        VStack(spacing: 2) {
                            Text(remainingText)
                                .font(.system(size: 56, weight: .light).monospacedDigit())
                                .contentTransition(.numericText())
                            Text(caption)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }

                    Section {
                        ForEach(options, id: \.0) { mode, label in
                            Button {
                                withAnimation { selection = mode }
                            } label: {
                                HStack {
                                    Text(label).foregroundStyle(Color.primary)
                                    Spacer()
                                    if selection == mode {
                                        Image(systemName: "checkmark")
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .accessibilityAddTraits(selection == mode ? .isSelected : [])
                        }
                    }

                    Section {
                        Toggle("结束前慢慢调小声", isOn: $fadeOut)
                    } footer: {
                        Text("最后 30 秒淡出，不会突然停止。")
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
            }
            .navigationTitle("睡眠定时")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { apply() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            selection = playback.sleepMode
            fadeOut = playback.fadeOut
        }
    }

    private var isLive: Bool { selection == playback.sleepMode && selection != .off }

    private var remainingText: String {
        if isLive, let remaining = playback.sleepRemaining { return DurationFormat.clock(remaining) }
        switch selection {
        case .off: return "--:--"
        case .minutes(let m): return DurationFormat.clock(TimeInterval(m * 60))
        case .endOfTrack:
            guard let duration = playback.duration else { return "--:--" }
            return DurationFormat.clock(max(0, duration - playback.elapsed))
        }
    }

    private var caption: String {
        switch selection {
        case .off: "定时已关闭"
        case .minutes: isLive ? "时间到了自动停止播放" : "按 ✓ 开始计时"
        case .endOfTrack: "这首播完就停"
        }
    }

    private func apply() {
        playback.fadeOut = fadeOut
        if selection != playback.sleepMode {
            playback.setSleepTimer(selection)
        }
        dismiss()
    }
}
