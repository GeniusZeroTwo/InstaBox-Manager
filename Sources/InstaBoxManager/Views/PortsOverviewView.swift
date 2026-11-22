import AppKit
import SwiftUI

struct PortsOverviewView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 12) {
            GlassEffectContainer {
                HStack(spacing: 14) {
                    GlassIconOrb(
                        systemImage: "network",
                        tint: .teal,
                        size: 40,
                        iconSize: 18,
                        cornerRadius: 13
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("已发布端口")
                            .font(.title3.weight(.semibold))
                        Text("查看并管理当前工作区所有沙盒暴露的公开与私密 HTTPS 域名。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                }
                .padding(18)
                .glassCard(cornerRadius: 20, tint: .teal.opacity(0.05))
            }
            .padding([.horizontal, .top], 14)

            if store.allPorts.isEmpty {
                ContentUnavailableView(
                    "暂无已发布端口",
                    systemImage: "network.slash",
                    description: Text("可在任意沙盒详情页的「SSH 与端口」标签页内添加要暴露的端口。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCard(cornerRadius: 20)
                .padding([.horizontal, .bottom], 14)
            } else {
                ScrollView {
                    GlassEffectContainer(spacing: 12) {
                        LazyVStack(spacing: 10) {
                            ForEach(store.allPorts) { item in
                                let machineName = store.machines.first(where: { $0.id == item.machineId })?.name ?? item.machineId
                                HStack(spacing: 14) {
                                    Text(":\(item.port)")
                                        .font(.system(.body, design: .monospaced).bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .foregroundStyle(Color.accentColor)
                                        .glassPill(tint: .accentColor.opacity(0.18))

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(machineName)
                                                .font(.subheadline.bold())
                                            Text(item.access == "private" ? "私密令牌" : "公开访问")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2)
                                                .foregroundStyle(item.access == "private" ? .orange : .green)
                                                .glassPill(tint: (item.access == "private" ? Color.orange : Color.green).opacity(0.18))
                                        }
                                        Text(item.tokenUrl ?? item.url)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }

                                    Spacer()

                                    Button("定位沙盒") {
                                        store.selectedMachineID = item.machineId
                                        store.selectedSection = .machines
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)

                                    Button("打开网页") {
                                        if let url = URL(string: item.tokenUrl ?? item.url) {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                    .buttonStyle(.glassProminent)
                                    .controlSize(.small)

                                    Button("复制") {
                                        TerminalLauncher.copyToClipboard(item.tokenUrl ?? item.url)
                                        store.showToast(.success, "链接已复制")
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)

                                    Button(role: .destructive) {
                                        unpublish(item)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)
                                    .help("取消发布端口")
                                    .accessibilityLabel("取消发布端口 \(item.port)")
                                }
                                .padding(16)
                                .glassCard(cornerRadius: 18, interactive: true)
                                .liquidHoverLift(scale: 1.008, liftY: -1.5, glowColor: .teal)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                        .animation(LiquidMotion.fluid, value: store.allPorts.map(\.id))
                    }
                }
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            }
        }
        .navigationTitle("公网端口")
    }

    private func unpublish(_ item: PublicPortItem) {
        guard let client = store.client else { return }
        Task {
            do {
                try await client.unpublishPort(machineId: item.machineId, port: item.port)
                store.showToast(.info, "已移除端口 \(item.port)")
                await store.refreshAll(silent: true)
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }
}
