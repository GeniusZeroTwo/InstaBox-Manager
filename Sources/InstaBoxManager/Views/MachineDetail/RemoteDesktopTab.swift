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

    private let resolutions: [(String, Int, Int)] = [
        ("1280x800", 1280, 800),
        ("1440x900", 1440, 900),
        ("1920x1080", 1920, 1080)
    ]

    var body: some View {
        VStack(spacing: 10) {
            // Floating Liquid Glass Control Strip
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 12) {
                    HStack(spacing: 7) {
                        LivePulseDot(
                            color: status?.running == true ? .green : (status?.installing == true ? .orange : .secondary),
                            isPulsing: status?.running == true,
                            size: 8
                        )
                        Text(statusText)
                            .font(.subheadline.weight(.medium))
                            .contentTransition(.interpolate)
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
                    .frame(width: 150)

                    Toggle("仅观看 (只读)", isOn: $viewOnly)
                        .font(.caption)

                    if status?.installed == false && status?.installing != true {
                        Button("安装桌面环境") {
                            performDesktopAction("install")
                        }
                        .buttonStyle(.glass)
                        .disabled(isBusy || machine.state != .running)
                    }

                    Button(status?.running == true ? "连接 / 刷新桌面画面" : "启动并连接桌面") {
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
                .padding(12)
                .glassCard(cornerRadius: 16, elevated: false)
            }
            .padding(.horizontal, 12)

            Group {
                if machine.state != .running {
                    ContentUnavailableView("沙盒未运行", systemImage: "display.trianglebadge.exclamationmark", description: Text("请先启动沙盒后再连接 Linux / Android / Omarchy 远程桌面。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .glassCard(cornerRadius: 18)
                } else if let stream = streamInfo, let url = URL(string: stream.url) {
                    RemoteDesktopWebView(url: url)
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
                            Text("点击上方「启动并连接桌面」即可在面板内直接操控云端浏览器与桌面（需使用沙盒创建者的个人 API Key 生成免登录流连接）。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 460)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassCard(cornerRadius: 18)
                }
            }
            .padding([.horizontal, .bottom], 12)
        }
        .onAppear {
            if machine.state == .running {
                checkStatus()
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
