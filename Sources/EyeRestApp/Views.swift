import AppKit
import SwiftUI
import EyeRestCore

struct CompanionMark: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width / 24, y: rect.minY + y * rect.height / 24) }
        var path = Path()
        path.move(to: p(3, 10)); path.addCurve(to: p(10, 9), control1: p(4, 3), control2: p(8, 3))
        path.move(to: p(14, 9)); path.addCurve(to: p(21, 10), control1: p(16, 3), control2: p(20, 3))
        path.move(to: p(7, 15)); path.addQuadCurve(to: p(17, 15), control: p(12, 21))
        return path
    }
}

@MainActor enum TutuFrames {
    static let frames: [[NSImage]] = {
        guard let url = Bundle.main.url(forResource: "tutu-spritesheet", withExtension: "png"),
              let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        return (0...2).map { row in
            (0..<8).compactMap { col in
                guard let crop = cg.cropping(to: CGRect(x: col * 192, y: row * 208, width: 192, height: 208)) else { return nil }
                return NSImage(cgImage: crop, size: NSSize(width: 192, height: 208))
            }
        }
    }()
}

/// The first sprite is Tutu sitting and looking toward the user.
struct TutuPortrait: View {
    var body: some View {
        Group {
            if let image = TutuFrames.frames.first?.first {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                CompanionMark().stroke(.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .accessibilityLabel("图图坐着陪你")
    }
}

struct TutuView: View {
    var moving: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.14, paused: !moving || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let walk = moving && !reduceMotion
            let phase = time.truncatingRemainder(dividingBy: 12) / 6
            let right = phase < 1
            let x = right ? phase : 2 - phase
            let row = walk ? (right ? 1 : 2) : 0
            let frame = walk ? Int(time / 0.14) % 8 : 0
            ZStack {
                if TutuFrames.frames.count == 3, TutuFrames.frames[row].count > frame {
                    Image(nsImage: TutuFrames.frames[row][frame])
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(width: 128, height: 139)
                        .offset(x: walk ? (x - 0.5) * 176 : 0)
                } else {
                    CompanionMark().stroke(.secondary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 72, height: 72)
                }
            }
            .frame(width: 320, height: 145)
        }
        .accessibilityLabel("图图")
        .accessibilityHidden(true)
    }
}

struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

/// Clear Liquid Glass on small controls; never add a second dark panel over the overlay.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 24
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

struct MenuPopover: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Group {
            if model.engine.phase == .awaitingReturn { ReturnReadyView(model: model) }
            else { menuContent }
        }
    }
    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 9) {
                TutuPortrait().frame(width: 32, height: 35)
                Text("休息一下").font(.headline)
                Spacer()
                if model.engine.paused { Text("已暂停").font(.caption).foregroundStyle(.secondary) }
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(timeText)
                        .font(.system(size: 43, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle().stroke(.primary.opacity(0.09), lineWidth: 5)
                    Circle().trim(from: 0, to: progress).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                }.frame(width: 59, height: 59).accessibilityHidden(true)
            }
            Divider()
            Toggle("会议模式", isOn: Binding(get: { model.engine.inMeeting }, set: { $0 ? model.startMeeting() : model.endMeeting() }))
                .toggleStyle(.switch)
            if model.engine.inMeeting {
                VStack(alignment: .leading, spacing: 10) {
                    if let grace = model.engine.meetingGraceRemaining {
                        Label("即将结束 · \(AppModel.format(grace))", systemImage: "clock.badge.exclamationmark")
                            .font(.callout).foregroundStyle(.orange)
                        Text("会议未结束？请选择时长续时。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("会议剩余 \(AppModel.format(model.engine.meetingRemaining ?? 0))")
                            .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        ForEach([15, 30, 60], id: \.self) { minutes in
                            Button("\(minutes) 分钟") { model.startMeeting(minutes: minutes) }
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if model.engine.isDue {
                        Label("休息时间已到", systemImage: "circle.fill").font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
            Button { model.togglePause() } label: {
                HStack { Text(model.engine.paused ? "恢复提醒" : "暂停提醒"); Spacer(); Image(systemName: model.engine.paused ? "play.fill" : "pause.fill") }
            }.buttonStyle(.plain)
            Button { model.requestRest() } label: {
                HStack { Text("现在休息"); Spacer(); Image(systemName: "arrow.up.right") }
            }.buttonStyle(.plain).disabled(model.engine.paused)
            Divider()
            HStack {
                Button { model.showSettings?() } label: { Label("设置", systemImage: "gearshape") }.buttonStyle(.plain)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.font(.callout)
        }
        .padding(22).frame(width: 320)
        .background(GlassBackground(material: .popover))
        .preferredColorScheme(model.preferences.appearance.scheme)
    }
    private var timeText: String {
        AppModel.format(model.engine.phase == .resting ? model.engine.restRemaining : model.engine.remaining)
    }
    private var statusText: String {
        if model.engine.paused { return "已暂停 · 恢复后接着计时" }
        if model.engine.phase == .resting { return "正在休息" }
        if model.engine.isDue { return model.engine.inMeeting ? "会议期间仅轻提示" : "该休息一下了" }
        return model.engine.snoozed ? "距离延后提醒" : "距离下次休息"
    }
    private var progress: CGFloat {
        if model.engine.phase == .resting {
            return CGFloat(min(1, max(0, 1 - model.engine.restRemaining / model.preferences.timing.restSeconds)))
        }
        let total = model.engine.snoozed ? model.preferences.timing.snoozeSeconds : model.preferences.timing.workSeconds
        return CGFloat(min(1, max(0, 1 - model.engine.remaining / total)))
    }
}

struct ReturnReadyView: View {
    @ObservedObject var model: AppModel
    private var tip: String {
        let tips = ["回来前，再看看窗外的远处。", "坐回来后，记得轻轻眨眨眼。", "顺便活动一下肩颈，调整坐姿。", "不着急，图图会在这里等你。"]
        return tips[max(0, model.engine.completedRests - 1) % tips.count]
    }
    var body: some View {
        VStack(spacing: 12) {
            TutuView(moving: false).scaleEffect(0.72).frame(height: 105)
            Text("图图等你回来").font(.system(size: 22, weight: .semibold))
            Text("这一轮休息结束了。\n回来操作电脑，就会自动开始下一轮。")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text(tip).font(.callout).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            Button { model.startNextCycle() } label: {
                Text("开始下一轮 · \(Int(model.preferences.timing.workSeconds / 60)) 分钟")
                    .font(.system(size: 15, weight: .medium)).frame(maxWidth: .infinity).frame(height: 42)
            }.buttonStyle(.plain).foregroundStyle(.white)
                .background(Color.accentColor, in: Capsule()).disabled(model.engine.suspended)
            Button("再休息一会儿") { model.keepResting() }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
            Text("暂不计时，键盘或鼠标活动后自动继续。\n术后用眼仍按医生建议安排。")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .padding(22).frame(width: 320, height: 505)
        .background(GlassBackground(material: .popover))
        .preferredColorScheme(model.preferences.appearance.scheme)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: preference(\.appearance)) {
                    ForEach(Preferences.Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Toggle("图图走动动画", isOn: preference(\.animateTutu))
                Text("系统开启“减少动态效果”时，图图会静止展示。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("休息节奏") {
                Stepper(value: timing(\.workSeconds, divisor: 60), in: 1...120) { settingRow("使用时长", "\(Int(model.preferences.timing.workSeconds / 60)) 分钟") }
                Stepper(value: timing(\.restSeconds), in: 10...300, step: 5) { settingRow("休息时长", "\(Int(model.preferences.timing.restSeconds)) 秒") }
                Stepper(value: timing(\.snoozeSeconds, divisor: 60), in: 1...30) { settingRow("延后时长", "\(Int(model.preferences.timing.snoozeSeconds / 60)) 分钟") }
                Text("锁屏或睡眠满休息时长后，重新开始计时。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("会议") {
                Picker("默认会议时长", selection: preference(\.meetingMinutes)) {
                    ForEach([15, 30, 60], id: \.self) { Text("\($0) 分钟").tag($0) }
                }
                Text("手动开启会议模式。到休息时间只改变菜单栏图标；会议模式到期有 1 分钟续时窗口。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("通用") {
                Toggle("休息结束提示音", isOn: preference(\.playSound))
                Toggle("登录时启动", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                if model.loginNeedsApproval {
                    Button("前往系统设置允许登录启动") { model.openLoginSettings() }
                }
                if let error = model.loginError { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Section {
                HStack {
                    CompanionMark().stroke(.secondary, style: StrokeStyle(lineWidth: 1.6, lineCap: .round)).frame(width: 22, height: 22)
                    Text("休息一下 · 图图陪你歇一会儿").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("1.0").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(GlassBackground(material: .underWindowBackground))
        .frame(width: 500, height: 640)
        .preferredColorScheme(model.preferences.appearance.scheme)
        .onAppear { if !model.diagnostic { model.refreshLoginStatus() } }
    }
    private func preference<T>(_ key: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { model.preferences[keyPath: key] }, set: { model.preferences[keyPath: key] = $0; model.savePreferences() })
    }
    private func timing(_ key: WritableKeyPath<RestSettings, Double>, divisor: Double = 1) -> Binding<Int> {
        Binding(get: { Int(model.preferences.timing[keyPath: key] / divisor) }, set: { model.preferences.timing[keyPath: key] = Double($0) * divisor; model.savePreferences() })
    }
    private func settingRow(_ name: String, _ value: String) -> some View {
        HStack { Text(name); Spacer(); Text(value).foregroundStyle(.secondary).monospacedDigit() }.padding(.trailing, 10)
    }
}

struct RestOverlay: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var resting: Bool { model.engine.phase == .resting }
    private var snoozeDuration: String {
        let seconds = model.preferences.timing.snoozeSeconds
        return seconds < 60 ? "\(Int(ceil(seconds))) 秒" : "\(Int(seconds / 60)) 分钟"
    }
    var body: some View {
        ZStack {
            // Behind-window vibrancy blurs the real desktop, not a captured image.
            GlassBackground(material: .underWindowBackground)
            (scheme == .dark ? Color.black : Color.white)
                .opacity(reduceTransparency ? 1 : (scheme == .dark ? 0.22 : 0.12))
            VStack(spacing: 0) {
                // Sitting portrait remains visible throughout rest; no walking or disappearance.
                TutuView(moving: model.preferences.animateTutu && !resting)
                    .padding(.bottom, 25)
                Text(resting ? "安心休息一会儿" : "该休息一下了")
                    .foregroundStyle(scheme == .dark ? Color.white : Color.black)
                    .font(.system(size: resting ? 34 : 42, weight: .semibold))
                    .padding(.bottom, 16)
                Text(resting && model.preferences.playSound ? "看向远处，结束时会有轻柔提示音" : "暂时离开屏幕，看向远处")
                    .font(.system(size: 18)).foregroundStyle((scheme == .dark ? Color.white : Color.black).opacity(0.72))
                    .padding(.bottom, 35)
                if !resting {
                    Button { model.beginRest() } label: {
                        Text("开始休息").font(.system(size: 17, weight: .medium)).frame(width: 250, height: 46)
                    }.buttonStyle(.plain).foregroundStyle(.white)
                        .background(Color.accentColor, in: Capsule()).padding(.bottom, 14)
                }
                HStack(spacing: 12) {
                    Button("延后 \(snoozeDuration)") { model.snooze() }
                    Button("跳过本次") { model.skip() }
                }.buttonStyle(RestSecondaryButton())
                    .foregroundStyle(scheme == .dark ? Color.white : Color.black)
                Text(resting ? (model.resetMessage ? "检测到操作，请再安心休息一会儿" : "不必看时间，安心看向远处") : "")
                    .font(.caption).foregroundStyle((scheme == .dark ? Color.white : Color.black).opacity(0.55))
                    .frame(height: 20).padding(.top, 22)
            }
            .padding(.horizontal, 48).padding(.vertical, 36)
            .frame(width: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .preferredColorScheme(model.preferences.appearance.scheme)
    }
}
struct RestSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14)).padding(.horizontal, 22).padding(.vertical, 10)
            .modifier(GlassSurface(cornerRadius: 24))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
