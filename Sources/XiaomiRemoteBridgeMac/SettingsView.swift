import AppKit
import Combine
import CoreBluetooth
import SwiftUI

private struct ShortcutRecordingTarget: Equatable {
    let profile: MappingProfile
    let button: RemoteButton
    let gesture: ButtonGesture
}

struct SettingsView: View {
    @ObservedObject var model: BridgeAppModel
    @ObservedObject var settings: AppSettings
    @State private var selectedRemoteButton: RemoteButton = .ok
    @State private var selectedProfile: MappingProfile = .general
    @State private var recordingTarget: ShortcutRecordingTarget?
    @State private var shortcutMonitor: Any?
    @State private var frontmostBundleIdentifier: String?
    @State private var inputMonitoringGranted = false
    @State private var accessibilityGranted = false
    @State private var bluetoothGranted = false

    init(model: BridgeAppModel) {
        self.model = model
        settings = model.settings
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("连接", systemImage: "antenna.radiowaves.left.and.right") }
            mappingTab
                .tabItem { Label("按键", systemImage: "keyboard") }
            permissionsTab
                .tabItem { Label("权限", systemImage: "lock.shield") }
        }
        .frame(width: 760, height: 600)
        .padding()
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusOverviewCard

                sectionHeader("语音输出")
                card {
                    HStack {
                        Text("语音输出")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.selectedAudioDeviceUID },
                            set: { value in
                                settings.selectedAudioDeviceUID = value
                                model.applyAudioSettings()
                            }
                        )) {
                            Text("不输出语音").tag("")
                            ForEach(model.audioDevices) { device in
                                Text(device.name).tag(device.uid)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    HStack {
                        Text("增益")
                        Slider(value: Binding(
                            get: { settings.gainDB },
                            set: { settings.gainDB = $0 }
                        ), in: 0...24, step: 1)
                        .frame(maxWidth: 320)
                        Text("\(Int(settings.gainDB)) dB")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 52, alignment: .trailing)
                        Spacer()
                    }

                    statusRow("音频状态", value: model.audioStatus)

                    Divider()

                    HStack(spacing: 10) {
                        Button("发送 1 秒测试音") { model.sendTestTone() }
                            .disabled(!model.canSendTestTone)
                        Text(model.testToneStatus)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Text("测试音只在内存生成、低音量、固定频率，不落盘；RC003 语音进行中时不可用。")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Divider()

                    HStack(spacing: 12) {
                        Button("刷新音频设备") { model.refreshAudioDevices() }
                        Link("获取 BlackHole", destination: URL(string: "https://existential.audio/blackhole/")!)
                    }
                    Text("应用只把 RC003 语音写到所选设备，不会修改系统默认输入或输出。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var statusOverviewCard: some View {
        card {
            HStack(alignment: .center, spacing: 12) {
                StatusDot(isStreaming: model.isStreaming, isConnected: model.isConnected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isStreaming ? "正在语音" : model.connectionStatus)
                        .font(.title3.weight(.semibold))
                    if model.isStreaming {
                        Text(model.connectionStatus)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("立即重新连接") { model.reconnect() }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 24) {
                    statusFact(
                        icon: model.isStreaming ? "mic.fill" : "mic",
                        text: model.isStreaming ? "语音中" : "等待麦克风键",
                        tint: model.isStreaming ? .orange : .secondary
                    )
                    statusFact(
                        icon: "speaker.wave.2",
                        text: audioOutputName,
                        tint: .secondary
                    )
                    Spacer()
                }
                statusFact(
                    icon: "globe",
                    text: model.voiceShortcutStatus,
                    tint: .secondary
                )
            }
        }
    }

    private var audioOutputName: String {
        let uid = settings.selectedAudioDeviceUID
        guard !uid.isEmpty else { return "不输出语音" }
        return model.audioDevices.first { $0.uid == uid }?.name ?? uid
    }

    private func card<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.leading, 2)
    }

    private func statusFact(
        icon: String,
        text: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 16, alignment: .center)
            Text(text)
                .font(.callout)
                .foregroundColor(tint)
                .lineLimit(1)
        }
    }

    private var mappingTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("启用 RC003 自定义按键映射", isOn: Binding(
                    get: { settings.customMappingEnabled },
                    set: { enabled in
                        settings.customMappingEnabled = enabled
                        model.applyHIDSettings()
                    }
                ))
                    statusRow("按键状态", value: model.hidStatus)
                    Text("优先独占 RC003；系统不允许独占时自动使用兼容监听，并只在遥控器原始报告附近拦截对应的系统按键，避免影响其他键盘。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(6)
            }

            HStack(alignment: .top, spacing: 16) {
                RemoteControlDiagram(
                    selectedButton: $selectedRemoteButton,
                    voiceActive: model.isStreaming
                )
                    .frame(width: 210)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Picker("配置", selection: $selectedProfile) {
                        ForEach(MappingProfile.allCases) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("当前前台应用：\(activeProfile.displayName) 配置")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if selectedProfile == .claudeCode {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("使用 Claude Code 配置的应用")
                                .font(.caption.weight(.semibold))
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), alignment: .leading),
                                    GridItem(.flexible(), alignment: .leading),
                                ],
                                alignment: .leading,
                                spacing: 4
                            ) {
                                ForEach(AppSettings.claudeHostCandidates) { host in
                                    Toggle(host.name, isOn: claudeHostBinding(host))
                                        .toggleStyle(.checkbox)
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("按键动作")
                                .font(.headline)
                            Text("点击左侧按键定位；单击和长按修改后自动保存。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("恢复默认") {
                            settings.resetBindings(for: selectedProfile)
                            selectedRemoteButton = .ok
                        }
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 7) {
                                ForEach(RemoteButton.allCases) { button in
                                    mappingRow(button)
                                        .id(button.id)
                                }
                            }
                            .padding(.trailing, 10)
                        }
                        .onChange(of: selectedRemoteButton) { button in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(button.id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .padding(4)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
        .onDisappear { stopShortcutRecording() }
        .onChange(of: selectedProfile) { _ in stopShortcutRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            stopShortcutRecording()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didActivateApplicationNotification
        )) { notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            frontmostBundleIdentifier = application?.bundleIdentifier
        }
    }

    private func mappingRow(_ button: RemoteButton) -> some View {
        let mapping = settings.mapping(for: button, profile: selectedProfile)
        return HStack(spacing: 12) {
            Button {
                selectedRemoteButton = button
            } label: {
                HStack(spacing: 9) {
                    Text(button.shortLabel)
                        .font(.caption.weight(.semibold))
                        .frame(width: 42, height: 30)
                        .background(
                            selectedRemoteButton == button
                                ? Color.accentColor
                                : Color.secondary.opacity(0.14)
                        )
                        .foregroundColor(selectedRemoteButton == button ? .white : .primary)
                        .clipShape(Capsule())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(button.displayName)
                        Text(String(format: "HID 0x%02X", button.hidUsage))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .frame(width: 150, alignment: .leading)

            Spacer()

            VStack(spacing: 6) {
                bindingEditor(
                    for: button,
                    gesture: .press,
                    dimmed: mapping.binding(for: .press).isDisabled
                )
                bindingEditor(
                    for: button,
                    gesture: .hold,
                    dimmed: mapping.binding(for: .hold).isDisabled
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            selectedRemoteButton == button
                ? Color.accentColor.opacity(0.09)
                : Color.secondary.opacity(0.055)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    selectedRemoteButton == button
                        ? Color.accentColor.opacity(0.45)
                        : Color.clear,
                    lineWidth: 1
                )
        )
    }

    private func bindingEditor(
        for button: RemoteButton,
        gesture: ButtonGesture,
        dimmed: Bool
    ) -> some View {
        let target = ShortcutRecordingTarget(
            profile: selectedProfile,
            button: button,
            gesture: gesture
        )
        let binding = settings.mapping(for: button, profile: selectedProfile)
            .binding(for: gesture)

        return HStack(spacing: 8) {
            Text(gesture.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .leading)
                .opacity(dimmed ? 0.6 : 1)

            if recordingTarget == target {
                Text("请按快捷键，Esc 取消")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                Picker("", selection: Binding(
                    get: {
                        settings.mapping(for: button, profile: selectedProfile)
                            .binding(for: gesture)
                    },
                    set: { setBinding($0, target: target) }
                )) {
                    if case .shortcut = binding {
                        Text(binding.displayName).tag(binding)
                    }
                    ForEach(ButtonAction.allCases) { action in
                        Text(action.displayName).tag(ButtonBinding.preset(action))
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                .opacity(dimmed ? 0.55 : 1)
                .help(binding.displayName)
            }

            Button {
                if recordingTarget == target {
                    stopShortcutRecording()
                } else {
                    startShortcutRecording(for: target)
                }
            } label: {
                Image(systemName: recordingTarget == target ? "xmark.circle" : "keyboard")
            }
            .buttonStyle(.borderless)
            .frame(width: 24, height: 24)
            .help(recordingTarget == target ? "取消录制" : "录制快捷键")
            .accessibilityLabel(recordingTarget == target ? "取消录制" : "录制快捷键")
        }
    }

    private func startShortcutRecording(for target: ShortcutRecordingTarget) {
        stopShortcutRecording()
        recordingTarget = target
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([
                .control, .option, .shift, .command,
            ])
            if event.keyCode == 53, modifiers.isEmpty {
                stopShortcutRecording()
                return nil
            }

            let combo = KeyCombo(
                keyCode: event.keyCode,
                keyLabel: ShortcutKeyLabel.name(
                    keyCode: event.keyCode,
                    characters: event.charactersIgnoringModifiers
                ),
                control: modifiers.contains(.control),
                option: modifiers.contains(.option),
                shift: modifiers.contains(.shift),
                command: modifiers.contains(.command)
            )
            setBinding(.shortcut(combo), target: target)
            stopShortcutRecording()
            return nil
        }
    }

    private func setBinding(
        _ binding: ButtonBinding,
        target: ShortcutRecordingTarget
    ) {
        let shouldApplyHIDSettings = !settings.customMappingEnabled
        settings.setBinding(
            binding,
            for: target.button,
            gesture: target.gesture,
            profile: target.profile
        )
        if shouldApplyHIDSettings {
            model.applyHIDSettings()
        }
    }

    private func stopShortcutRecording() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
        recordingTarget = nil
    }

    private var activeProfile: MappingProfile {
        settings.profile(forBundleIdentifier: frontmostBundleIdentifier)
    }

    private func claudeHostBinding(_ host: ClaudeHostApplication) -> Binding<Bool> {
        Binding(
            get: { settings.claudeHostBundleIDs.contains(host.bundleIdentifier) },
            set: { enabled in
                var hosts = settings.claudeHostBundleIDs
                if enabled {
                    hosts.insert(host.bundleIdentifier)
                } else {
                    hosts.remove(host.bundleIdentifier)
                }
                settings.claudeHostBundleIDs = hosts
            }
        )
    }

    private var permissionsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("所需权限")
                card {
                    permissionRow(
                        icon: "dot.radiowaves.left.and.right",
                        iconTint: .blue,
                        title: "蓝牙",
                        detail: "连接 RC003 并读取 ATVV 语音服务",
                        granted: bluetoothGranted,
                        actionTitle: "打开蓝牙设置"
                    ) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Divider()
                    permissionRow(
                        icon: "keyboard",
                        iconTint: Color(NSColor.systemIndigo),
                        title: "输入监控",
                        detail: "读取 RC003 原始 HID 报告，并在兼容模式下抑制重复系统事件",
                        granted: inputMonitoringGranted,
                        actionTitle: "请求权限"
                    ) { model.requestInputMonitoringPermission() }
                    Divider()
                    permissionRow(
                        icon: "accessibility",
                        iconTint: .green,
                        title: "辅助功能",
                        detail: "把映射后的按键动作发送给当前应用",
                        granted: accessibilityGranted,
                        actionTitle: "请求权限"
                    ) { model.requestAccessibilityPermission() }
                }

                sectionHeader("诊断")
                card {
                    HStack {
                        Button("在 Finder 中显示日志") { model.openLogFolder() }
                        Spacer()
                    }
                    Text("日志不记录语音内容、蓝牙地址或外设 UUID。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private func refreshPermissions() {
        inputMonitoringGranted = HIDRemoteMonitor.isInputMonitoringGranted
        accessibilityGranted = KeyboardInjector.isAccessibilityTrusted
        bluetoothGranted = CBCentralManager.authorization == .allowedAlways
    }

    private func permissionRow(
        icon: String,
        iconTint: Color,
        title: String,
        detail: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(granted ? iconTint : Color.secondary.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if granted {
                Label("已授权", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundColor(.green)
            } else {
                Button(actionTitle, action: action)
            }
        }
    }

    private func statusRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

private struct RemoteControlDiagram: View {
    @Binding var selectedButton: RemoteButton
    let voiceActive: Bool

    private static let photo: NSImage? = {
        guard let url = Bundle.main.url(
            forResource: "RC003-remote-photo",
            withExtension: "png"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                ZStack {
                    if let photo = Self.photo {
                        Image(nsImage: photo)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.secondary.opacity(0.10))
                        Text("实物图资源缺失")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    hotspot(.power, x: 0.386, y: 0.099, width: 0.15, height: 0.072)
                    voiceHotspot(x: 0.630, y: 0.099, width: 0.15, height: 0.072)

                    hotspot(.up, x: 0.502, y: 0.179, width: 0.18, height: 0.065)
                    hotspot(.left, x: 0.362, y: 0.246, width: 0.15, height: 0.080)
                    hotspot(.ok, x: 0.502, y: 0.246, width: 0.19, height: 0.095)
                    hotspot(.right, x: 0.638, y: 0.246, width: 0.15, height: 0.080)
                    hotspot(.down, x: 0.502, y: 0.317, width: 0.18, height: 0.065)

                    hotspot(.back, x: 0.406, y: 0.389, width: 0.17, height: 0.080)
                    hotspot(.volumeUp, x: 0.604, y: 0.390, width: 0.16, height: 0.080)
                    hotspot(.home, x: 0.406, y: 0.479, width: 0.17, height: 0.080)
                    hotspot(.volumeDown, x: 0.604, y: 0.480, width: 0.16, height: 0.080)
                    hotspot(.menu, x: 0.406, y: 0.569, width: 0.17, height: 0.080)
                    hotspot(.tv, x: 0.604, y: 0.569, width: 0.17, height: 0.080)
                }
            }
            .frame(width: 210, height: 426)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
            )

            Text("点击实物按键定位映射；麦克风键固定为硬件语音/Fn。")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func hotspot(
        _ button: RemoteButton,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        Button {
            selectedButton = button
        } label: {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(
                    selectedButton == button
                        ? Color.accentColor.opacity(0.27)
                        : Color.clear
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .stroke(
                            selectedButton == button ? Color.accentColor : Color.clear,
                            lineWidth: 2
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(width: 210 * width, height: 426 * height)
        .position(x: 210 * x, y: 426 * y)
        .help(button.displayName)
        .accessibilityLabel(Text(button.displayName))
    }

    private func voiceHotspot(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        Circle()
            .fill(voiceActive ? Color.orange.opacity(0.30) : Color.clear)
            .overlay(
                Circle().stroke(
                    voiceActive ? Color.orange : Color.clear,
                    lineWidth: 2
                )
            )
            .contentShape(Circle())
            .frame(width: 210 * width, height: 426 * height)
            .position(x: 210 * x, y: 426 * y)
        .help("遥控器真实 F5 硬件按下/松开会映射为 Mac Fn；同时桥接 ATVV 语音")
        .accessibilityElement()
        .accessibilityLabel(Text("语音/Fn 键，固定核心功能"))
    }
}

private struct StatusDot: View {
    let isStreaming: Bool
    let isConnected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private var dotColor: Color {
        if isStreaming { return .orange }
        return isConnected ? .green : Color.secondary.opacity(0.5)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.35))
                .frame(width: 30, height: 30)
                .scaleEffect(pulsing ? 1.45 : 0.9)
                .opacity(isStreaming ? (pulsing ? 0 : 0.9) : 0)
            Circle()
                .fill(dotColor)
                .frame(width: 13, height: 13)
        }
        .frame(width: 34, height: 34)
        .onAppear { updatePulse() }
        .onChange(of: isStreaming) { _ in updatePulse() }
    }

    private func updatePulse() {
        if isStreaming, !reduceMotion {
            guard !pulsing else { return }
            withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pulsing = false
            }
        }
    }
}
