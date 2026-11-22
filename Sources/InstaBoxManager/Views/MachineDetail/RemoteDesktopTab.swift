import AppKit
import SwiftUI

struct RemoteDesktopTab: View {
    @Environment(AppStore.self) private var store
    let machine: MachineItem

    @ViewState private var status: DesktopStatusResponse?
    @ViewState private var streamInfo: DesktopStreamResponse?
    @ViewState private var resolutionChoice: String = "1280x800"
    @ViewState private var viewOnly: Bool = false
    @ViewState private var isBusy = false

    // Bidirectional Clipboard Sync State
    @ViewState private var autoSyncClipboard: Bool = true
    @ViewState private var isSyncingClipboard = false
    @ViewState private var lastSyncedText: String = ""
    @ViewState private var lastLocalChangeCount: Int = NSPasteboard.general.changeCount
    @ViewState private var webViewMacClipText: String? = nil
    @ViewState private var webViewMacClipRevision: Int = 0
    @ViewState private var lastSyncDirectionLabel: String? = nil
    @ViewState private var sandboxToolUnsupported = false
    @ViewState private var clipboardSyncTask: Task<Void, Never>? = nil

    private let resolutions: [(String, Int, Int)] = [
        ("1280x800", 1280, 800),
        ("1440x900", 1440, 900),
        ("1920x1080", 1920, 1080)
    ]

    var body: some View {
        VStack(spacing: 10) {
            // Floating Liquid Glass Control Strip
            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        HStack(spacing: 7) {
                            LivePulseDot(
                                color: status?.running == true ? .green : (status?.installing == true ? .orange : .secondary),
                                isPulsing: status?.running == true,
                                size: 8
                            )
                            Text(statusText)
                                .font(.subheadline.weight(.medium))
                                .contentTransition(.interpolate)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassPill()

                        Spacer()

                        Picker("分辨率", selection: $resolutionChoice) {
                            ForEach(resolutions, id: \.0) { r in
                                Text(r.0).tag(r.0)
                            }
                        }
                        .frame(width: 140)

                        Toggle("仅观看", isOn: $viewOnly)
                            .font(.caption)

                        if status?.installed == false && status?.installing != true {
                            Button("安装桌面环境") {
                                performDesktopAction("install")
                            }
                            .buttonStyle(.glass)
                            .disabled(isBusy || machine.state != .running)
                        }

                        Button(status?.running == true ? "连接 / 刷新画面" : "启动并连接桌面") {
                            startAndConnectDesktop()
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(isBusy || machine.state != .running)

                        if let stream = streamInfo, let url = URL(string: stream.url) {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Image(systemName: "safari")
                            }
                            .buttonStyle(.glass)
                            .help("在默认浏览器全屏打开")

                            Button {
                                TerminalLauncher.copyToClipboard(stream.url)
                                store.showToast(.success, "桌面分享链接已复制")
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.glass)
                            .help("复制临时远程桌面链接")

                            Button(role: .destructive) {
                                revokeLinks()
                            } label: {
                                Image(systemName: "xmark.shield")
                            }
                            .buttonStyle(.glass)
                            .help("吊销所有已分享的远程桌面链接")
                        }
                    }

                    // Bidirectional Clipboard Sync Bar
                    if machine.state == .running {
                        HStack(spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.left.arrow.right.circle.fill")
                                    .foregroundStyle(autoSyncClipboard ? Color.accentColor : .secondary)
                                Toggle("双向剪贴板自动同步 (Mac ⇄ 云端)", isOn: $autoSyncClipboard)
                                    .font(.caption.weight(.medium))
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                            }

                            if let dir = lastSyncDirectionLabel {
                                Text(dir)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2.5)
                                    .glassPill(tint: .accentColor.opacity(0.14))
                                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            }

                            Spacer()

                            Button {
                                pushLocalClipboardManually()
                            } label: {
                                Label("Mac → 云端", systemImage: "arrow.up.doc")
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .disabled(isSyncingClipboard)
                            .help("立即将本机 Mac 剪贴板写入云端沙盒剪贴板")

                            Button {
                                pullRemoteClipboardManually()
                            } label: {
                                Label("云端 → Mac", systemImage: "arrow.down.doc")
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .disabled(isSyncingClipboard)
                            .help("立即读取云端沙盒剪贴板到本机 Mac")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassWell(cornerRadius: 11)
                        .animation(LiquidMotion.snappy, value: lastSyncDirectionLabel)
                    }
                }
                .padding(12)
                .glassCard(cornerRadius: 16, elevated: false)
            }
            .padding(.horizontal, 12)

            Group {
                if machine.state != .running {
                    ContentUnavailableView(
                        "沙盒未运行",
                        systemImage: "display.trianglebadge.exclamationmark",
                        description: Text("请先启动沙盒后再连接 Linux / Android / Omarchy 远程桌面。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassCard(cornerRadius: 18)
                } else if let stream = streamInfo, let url = URL(string: stream.url) {
                    RemoteDesktopWebView(
                        url: url,
                        clipboardEnabled: autoSyncClipboard,
                        incomingMacText: webViewMacClipText,
                        incomingMacRevision: webViewMacClipRevision,
                        onRemoteCopiedText: { remoteText in
                            handleIncomingRemoteClipboard(remoteText, source: "网页桥接")
                        },
                        onCmdPasteTriggered: {
                            Task { await syncMacToSandboxSilently(force: true) }
                        },
                        onCmdCopyTriggered: {
                            Task {
                                try? await Task.sleep(for: .milliseconds(250))
                                await syncSandboxToMacSilently()
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassCard(cornerRadius: 20)
                } else {
                    VStack(spacing: 14) {
                        GlassIconOrb(systemImage: "display", tint: .accentColor, size: 64, iconSize: 28, cornerRadius: 20)
                        Text("远程图形桌面（X11 / Wayland / Android 屏幕）")
                            .font(.headline)
                        if let hint = status?.hint {
                            Text(hint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("点击上方「启动并连接桌面」即可在面板内直接操控云端浏览器与桌面，并默认开启 Mac ⇄ 云端双向剪贴板实时同步。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 480)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassCard(cornerRadius: 18)
                }
            }
            .padding([.horizontal, .bottom], 12)
        }
        .onAppear {
            lastLocalChangeCount = SandboxClipboardSync.localChangeCount()
            lastSyncedText = SandboxClipboardSync.readLocalText() ?? ""
            if machine.state == .running {
                checkStatus()
                restartClipboardSyncLoop()
            }
        }
        .onDisappear {
            clipboardSyncTask?.cancel()
            clipboardSyncTask = nil
        }
        .onChange(of: autoSyncClipboard) { _, _ in
            restartClipboardSyncLoop()
        }
        .onChange(of: machine.state) { _, newState in
            if newState == .running {
                restartClipboardSyncLoop()
            } else {
                clipboardSyncTask?.cancel()
                clipboardSyncTask = nil
            }
        }
    }

    private var statusText: String {
        guard let status else { return "检测状态中…" }
        if status.installing { return "正在安装桌面环境…" }
        if status.running { return "桌面运行中 (\(status.kind ?? "GUI"))" }
        if status.installed { return "桌面已安装（未启动）" }
        return "当前镜像未安装桌面组件"
    }

    // MARK: - Bidirectional Clipboard Engine

    private func restartClipboardSyncLoop() {
        clipboardSyncTask?.cancel()
        clipboardSyncTask = nil
        guard autoSyncClipboard, machine.state == .running else { return }

        lastLocalChangeCount = SandboxClipboardSync.localChangeCount()
        let initialText = SandboxClipboardSync.readLocalText() ?? ""
        if !initialText.isEmpty {
            webViewMacClipText = initialText
            webViewMacClipRevision += 1
        }

        clipboardSyncTask = Task {
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled, autoSyncClipboard, machine.state == .running else { break }

                // 1. Fast check: Mac NSPasteboard -> Sandbox
                let currentCount = SandboxClipboardSync.localChangeCount()
                if currentCount != lastLocalChangeCount {
                    lastLocalChangeCount = currentCount
                    await syncMacToSandboxSilently(force: false)
                } else if tick % 2 == 1, !sandboxToolUnsupported {
                    // 2. Periodic check (~1.5s): Sandbox OS Clipboard -> Mac NSPasteboard
                    await syncSandboxToMacSilently()
                }
                tick += 1
            }
        }
    }

    private func syncMacToSandboxSilently(force: Bool) async {
        guard let text = SandboxClipboardSync.readLocalText(), !text.isEmpty else { return }
        guard force || text != lastSyncedText else { return }

        lastSyncedText = text
        webViewMacClipText = text
        webViewMacClipRevision += 1

        guard let client = store.client, !sandboxToolUnsupported else { return }
        do {
            try await SandboxClipboardSync.pushToSandbox(client: client, machineId: machine.id, text: text)
            lastSyncDirectionLabel = "已同步 Mac → 云端"
        } catch SandboxClipboardError.clipboardToolUnavailable {
            sandboxToolUnsupported = true
        } catch {
            // Silent background failure; manual push button surfaces errors explicitly
        }
    }

    private func syncSandboxToMacSilently() async {
        guard let client = store.client else { return }
        do {
            let remoteText = try await SandboxClipboardSync.pullFromSandbox(client: client, machineId: machine.id)
            guard !remoteText.isEmpty, remoteText != lastSyncedText else { return }
            handleIncomingRemoteClipboard(remoteText, source: "云端桌面")
        } catch SandboxClipboardError.clipboardToolUnavailable {
            sandboxToolUnsupported = true
        } catch {
            // Empty or transient error; ignore during background polling
        }
    }

    private func handleIncomingRemoteClipboard(_ text: String, source: String) {
        guard !text.isEmpty, text != lastSyncedText else { return }
        lastSyncedText = text
        lastLocalChangeCount = SandboxClipboardSync.writeLocalText(text)
        lastSyncDirectionLabel = "已同步 \(source) → Mac"
    }

    private func pushLocalClipboardManually() {
        guard let client = store.client else { return }
        guard let text = SandboxClipboardSync.readLocalText(), !text.isEmpty else {
            store.showToast(.info, SandboxClipboardError.emptyLocalClipboard.localizedDescription)
            return
        }
        isSyncingClipboard = true
        webViewMacClipText = text
        webViewMacClipRevision += 1
        lastSyncedText = text
        lastLocalChangeCount = SandboxClipboardSync.localChangeCount()

        Task {
            defer { isSyncingClipboard = false }
            do {
                try await SandboxClipboardSync.pushToSandbox(client: client, machineId: machine.id, text: text)
                sandboxToolUnsupported = false
                lastSyncDirectionLabel = "已发送 Mac → 云端"
                store.showToast(.success, "已将本机剪贴板（\(text.count) 字符）发送到云端桌面，可直接 Ctrl+V 粘贴")
            } catch {
                store.showToast(.info, error.localizedDescription)
            }
        }
    }

    private func pullRemoteClipboardManually() {
        guard let client = store.client else { return }
        isSyncingClipboard = true
        Task {
            defer { isSyncingClipboard = false }
            do {
                let remoteText = try await SandboxClipboardSync.pullFromSandbox(client: client, machineId: machine.id)
                sandboxToolUnsupported = false
                lastSyncedText = remoteText
                lastLocalChangeCount = SandboxClipboardSync.writeLocalText(remoteText)
                lastSyncDirectionLabel = "已拉取 云端 → Mac"
                store.showToast(.success, "已读取云端剪贴板（\(remoteText.count) 字符）到本机，可直接 ⌘V 粘贴")
            } catch {
                store.showToast(.info, error.localizedDescription)
            }
        }
    }

    // MARK: - Desktop Lifecycle Actions

    private func checkStatus() {
        guard let client = store.client else { return }
        Task {
            if let st = try? await client.desktopAction(machineId: machine.id, request: DesktopActionRequest(action: "status")) {
                self.status = st
            }
        }
    }

    private func performDesktopAction(_ action: String) {
        guard let client = store.client else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let st = try await client.desktopAction(machineId: machine.id, request: DesktopActionRequest(action: action))
                self.status = st
                store.showToast(.info, action == "install" ? "已触发桌面组件安装，约需 30 秒…" : "桌面状态已更新")
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }

    private func startAndConnectDesktop() {
        guard let client = store.client else { return }
        isBusy = true
        let dims = resolutions.first(where: { $0.0 == resolutionChoice }) ?? ("1280x800", 1280, 800)

        Task {
            defer { isBusy = false }
            do {
                let st = try await client.desktopAction(
                    machineId: machine.id,
                    request: DesktopActionRequest(action: "start", width: dims.1, height: dims.2)
                )
                self.status = st
                if !st.installed {
                    store.showToast(.info, st.hint ?? "请先点击「安装桌面环境」")
                    return
                }
                let stream = try await client.createDesktopStream(
                    machineId: machine.id,
                    request: DesktopStreamRequest(viewOnly: viewOnly, ttlSeconds: 3600)
                )
                self.streamInfo = stream
                restartClipboardSyncLoop()
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }

    private func revokeLinks() {
        guard let client = store.client else { return }
        Task {
            do {
                try await client.revokeDesktopStreams(machineId: machine.id)
                streamInfo = nil
                store.showToast(.info, "已关闭并吊销远程桌面流连接")
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }
}
