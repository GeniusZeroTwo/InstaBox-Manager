import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var bindableStore = store

        Form {
            Section("偏好设置") {
                Picker("后台自动刷新频率", selection: $bindableStore.autoRefreshSeconds) {
                    Text("每 5 秒").tag(5)
                    Text("每 15 秒（推荐）").tag(15)
                    Text("每 30 秒").tag(30)
                    Text("每 60 秒").tag(60)
                    Text("手动刷新").tag(0)
                }

                Picker("默认 SSH 终端应用", selection: $bindableStore.preferredTerminal) {
                    ForEach(TerminalAppPreference.allCases) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }
            }

            Section("已保存的 API 密钥（钥匙串加密）") {
                if store.profiles.isEmpty {
                    Text("暂未保存任何 API Key")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.profiles) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).fontWeight(.medium)
                                Text("\(p.keyPrefix) · \(p.normalizedBaseURL)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if p.id == store.activeProfileID {
                                Text("当前使用")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(.green)
                                    .glassPill(tint: .green.opacity(0.20))
                            } else {
                                Button("切换") {
                                    store.switchProfile(p)
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                            }
                            Button(role: .destructive) {
                                store.removeProfile(p)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
                    }
                }
            }

            Section("关于客户端") {
                LabeledContent("运行架构", value: "arm64 (Apple Silicon Native)")
                LabeledContent("视觉引擎", value: "SwiftUI Liquid Glass Native")
                LabeledContent("协议规范", value: "InstaBox OpenAPI v1 (https://api.instabox.sh)")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .glassCard(cornerRadius: 20)
        .padding(12)
        .background { GlassBackdrop() }
    }
}

struct MenuBarContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    GlassIconOrb(systemImage: "cube.transparent.fill", tint: .accentColor, size: 28, iconSize: 13, cornerRadius: 9)
                    Text(store.activeProfile?.name ?? "InstaBox 管理面板")
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if store.isConnected {
                        Button {
                            Task { await store.refreshAll() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                }

                if !store.isConnected {
                    Text("尚未绑定 API Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                        .glassWell(cornerRadius: 10)
                } else if store.machines.isEmpty {
                    Text("当前工作区暂无沙盒实例")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                        .glassWell(cornerRadius: 10)
                } else {
                    VStack(spacing: 6) {
                        ForEach(store.machines.prefix(8)) { m in
                            HStack(spacing: 8) {
                                LivePulseDot(
                                    color: m.state == .running ? .green : (m.state == .suspended ? .indigo : .secondary),
                                    isPulsing: m.state == .running,
                                    size: 8
                                )

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(m.name)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Text(m.state.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if m.state == .running {
                                    Button("SSH") {
                                        Task { await store.openQuickSSH(for: m) }
                                    }
                                    .buttonStyle(.glassProminent)
                                    .controlSize(.mini)

                                    Button("暂停") {
                                        Task { await store.suspendMachine(m) }
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.mini)
                                } else if m.state == .suspended {
                                    Button("恢复") {
                                        Task { await store.resumeMachine(m) }
                                    }
                                    .buttonStyle(.glassProminent)
                                    .tint(.indigo)
                                    .controlSize(.mini)
                                } else if m.state == .stopped {
                                    Button("启动") {
                                        Task { await store.startMachine(m) }
                                    }
                                    .buttonStyle(.glassProminent)
                                    .tint(.green)
                                    .controlSize(.mini)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .liquidWellInteractive(cornerRadius: 10)
                        }
                    }
                }

                HStack {
                    Button("打开主面板") {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "main")
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)

                    Spacer()

                    Button("退出") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
                .padding(.top, 2)
            }
            .padding(14)
        }
        .frame(width: 340)
    }
}
