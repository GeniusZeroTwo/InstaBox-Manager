import AppKit
import SwiftUI

struct SSHAndPortsTab: View {
    @Environment(AppStore.self) private var store
    let machine: MachineItem

    @ViewState private var connInfo: ConnectionInfoResponse?
    @ViewState private var sshTokens: [SSHTokenInfoItem] = []
    @ViewState private var latestIssuedToken: SSHTokenResponse?
    @ViewState private var newTokenName: String = "macbook"
    @ViewState private var tokenTTLHours: Int = 24

    @ViewState private var ports: [PublicPortItem] = []
    @ViewState private var portNumberText: String = "3000"
    @ViewState private var portName: String = ""
    @ViewState private var portAccess: String = "public"
    @ViewState private var portProtocol: String = "http"
    @ViewState private var isWorking = false

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    sshSection
                    portsSection
                }
                .padding([.horizontal, .bottom], 14)
                .padding(.top, 4)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .onAppear {
            reloadAll()
        }
    }

    // MARK: - SSH Section

    private var sshSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 9) {
                    GlassIconOrb(systemImage: "terminal.fill", tint: LiquidPalette.statusBlue, size: 30, iconSize: 14, cornerRadius: 9)
                    Text("SSH / Mosh 免密直连")
                        .font(.headline)
                        .foregroundStyle(LiquidPalette.textPrimary)
                }
                Spacer()
                Button {
                    Task { await store.openQuickSSH(for: machine) }
                } label: {
                    Label("一键打开 \(store.preferredTerminal.rawValue) 连接 SSH", systemImage: "arrow.up.forward.app.fill")
                }
                .buttonStyle(.glassProminent)
            }

            if let info = connInfo {
                HStack(spacing: 18) {
                    Text("主机：\(info.host):\(info.port)")
                    Text("默认用户：\(info.username)")
                    Text("支持特性：\(info.capabilities.joined(separator: ", "))")
                }
                .font(.caption.monospaced())
                .foregroundStyle(LiquidPalette.textSecondary)
            }

            HStack(spacing: 10) {
                TextField("令牌备注名", text: $newTokenName)
                    .textFieldStyle(.plain)
                    .foregroundStyle(LiquidPalette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassWell(cornerRadius: 9)
                    .frame(width: 180)

                Picker("有效期", selection: $tokenTTLHours) {
                    Text("1 小时").tag(1)
                    Text("8 小时").tag(8)
                    Text("24 小时").tag(24)
                    Text("7 天").tag(168)
                    Text("永不过期").tag(0)
                }
                .frame(width: 160)

                Button("签发新 SSH 命令令牌") {
                    issueSSHToken()
                }
                .buttonStyle(.glass)
                .disabled(isWorking)

                if !sshTokens.isEmpty {
                    Button("吊销全部令牌", role: .destructive) {
                        revokeAllTokens()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }

            if let issued = latestIssuedToken {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("最新签发 SSH 命令（可直接粘贴到任意终端）：")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LiquidPalette.textPrimary)
                        Spacer()
                        Button("复制 SSH") {
                            TerminalLauncher.copyToClipboard(issued.command)
                            store.showToast(.success, "SSH 命令已复制")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)

                        if let mosh = issued.moshCommand {
                            Button("复制 Mosh") {
                                TerminalLauncher.copyToClipboard(mosh)
                                store.showToast(.success, "Mosh 命令已复制")
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
                    }
                    Text(issued.command)
                        .font(.system(.caption, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCodeCanvas(cornerRadius: 9)
                        .textSelection(.enabled)
                }
                .padding(12)
                .glassWell(cornerRadius: 12, tint: LiquidPalette.statusBlue)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !sshTokens.isEmpty {
                Text("已签发的 SSH 令牌记录")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiquidPalette.textSecondary)
                    .padding(.top, 2)

                ForEach(sshTokens.prefix(10)) { item in
                    HStack {
                        Text(item.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LiquidPalette.textPrimary)
                        Text(item.id)
                            .font(.caption2.monospaced())
                            .foregroundStyle(LiquidPalette.textMuted)
                        if item.revokedAt != nil {
                            Text("已吊销")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(LiquidPalette.statusRed)
                        } else if let exp = item.expiresAt {
                            Text("到期：\(Formatters.relativeOrShortTime(exp))")
                                .font(.caption2)
                                .foregroundStyle(LiquidPalette.textSecondary)
                        } else {
                            Text("长期有效")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(LiquidPalette.statusGreen)
                        }
                        Spacer()
                        if let cmd = item.command, item.revokedAt == nil {
                            Button("复制命令") {
                                TerminalLauncher.copyToClipboard(cmd)
                                store.showToast(.info, "已复制 SSH 命令")
                            }
                            .buttonStyle(.glass)
                            .controlSize(.mini)
                        }
                        if item.revokedAt == nil {
                            Button("吊销", role: .destructive) {
                                revokeSingleToken(item.id)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.mini)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .glassWell(cornerRadius: 9)
                }
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 18)
    }

    // MARK: - Public & Private Ports Section

    private var portsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 9) {
                    GlassIconOrb(systemImage: "globe", tint: LiquidPalette.statusTeal, size: 30, iconSize: 14, cornerRadius: 9)
                    Text("端口公网 / 私密 HTTPS 暴露")
                        .font(.headline)
                        .foregroundStyle(LiquidPalette.textPrimary)
                }
                Spacer()
                Button {
                    reloadAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }

            HStack(spacing: 10) {
                TextField("容器端口 (如 3000)", text: $portNumberText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(LiquidPalette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassWell(cornerRadius: 9)
                    .frame(width: 135)

                TextField("名称备注（可选）", text: $portName)
                    .textFieldStyle(.plain)
                    .foregroundStyle(LiquidPalette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassWell(cornerRadius: 9)
                    .frame(width: 165)

                Picker("访问权限", selection: $portAccess) {
                    Text("公开 (Public)").tag("public")
                    Text("私密令牌 (Private)").tag("private")
                }
                .frame(width: 185)

                Picker("协议", selection: $portProtocol) {
                    Text("HTTP").tag("http")
                    Text("TCP").tag("tcp")
                }
                .frame(width: 110)

                Button("发布端口") {
                    publishPort()
                }
                .buttonStyle(.glassProminent)
                .disabled(Int(portNumberText) == nil || isWorking)
            }

            if ports.isEmpty {
                Text("当前沙盒暂未暴露任何端口。在沙盒内启动 Web 服务（如 3000 / 8080 端口）后在此一键生成 HTTPS 域名。")
                    .font(.caption)
                    .foregroundStyle(LiquidPalette.textSecondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(ports) { p in
                    let accessColor = p.access == "private" ? LiquidPalette.statusOrange : LiquidPalette.statusGreen
                    HStack(spacing: 12) {
                        Text(":\(p.port)")
                            .font(.system(.subheadline, design: .monospaced).bold())
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .foregroundStyle(LiquidPalette.statusBlue)
                            .glassPill(tint: LiquidPalette.statusBlue)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(p.tokenUrl ?? p.url)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(LiquidPalette.textPrimary)
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                Text(p.access == "private" ? "私密链接" : "公开")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .foregroundStyle(accessColor)
                                    .glassPill(tint: accessColor)
                            }
                            if !p.name.isEmpty {
                                Text(p.name)
                                    .font(.caption2)
                                    .foregroundStyle(LiquidPalette.textMuted)
                            }
                        }

                        Spacer()

                        Button("浏览器打开") {
                            if let url = URL(string: p.tokenUrl ?? p.url) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)

                        Button("复制链接") {
                            TerminalLauncher.copyToClipboard(p.tokenUrl ?? p.url)
                            store.showToast(.success, "端口链接已复制")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)

                        Button(role: .destructive) {
                            unpublishPort(p.port)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                    .padding(11)
                    .liquidWellInteractive(cornerRadius: 11)
                }
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 18)
        .animation(LiquidMotion.fluid, value: ports.count)
    }

    // MARK: - Actions

    private func reloadAll() {
        guard let client = store.client else { return }
        Task {
            async let ci = try? client.fetchConnectionInfo(machineId: machine.id)
            async let tk = try? client.fetchSSHTokens(machineId: machine.id)
            async let pt = try? client.fetchMachinePorts(machineId: machine.id)

            if let c = await ci { connInfo = c }
            if let t = await tk { sshTokens = t }
            if let p = await pt { ports = p.ports }
        }
    }

    private func issueSSHToken() {
        guard let client = store.client else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let req = CreateSSHTokenRequest(
                    name: newTokenName.isEmpty ? "macbook" : newTokenName,
                    ttlSeconds: tokenTTLHours == 0 ? nil : tokenTTLHours * 3600,
                    noExpiry: tokenTTLHours == 0 ? true : nil
                )
                let res = try await client.createSSHToken(machineId: machine.id, request: req)
                latestIssuedToken = res
                TerminalLauncher.copyToClipboard(res.command)
                store.showToast(.success, "SSH 令牌已签发并复制命令到剪贴板")
                reloadAll()
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }

    private func revokeSingleToken(_ tokenId: String) {
        guard let client = store.client else { return }
        Task {
            do {
                try await client.revokeSSHToken(machineId: machine.id, tokenId: tokenId)
                reloadAll()
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }

    private func revokeAllTokens() {
        guard let client = store.client else { return }
        Task {
            do {
                try await client.revokeAllSSHTokens(machineId: machine.id)
                latestIssuedToken = nil
                store.showToast(.info, "已吊销所有 SSH 令牌")
                reloadAll()
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }

    private func publishPort() {
        guard let client = store.client, let port = Int(portNumberText), (1...65555).contains(port) || (1...65535).contains(port) else { return }
        guard (1...65535).contains(port) else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let req = PublishPortRequest(
                    port: port,
                    name: portName.isEmpty ? nil : portName,
                    access: portAccess,
                    protocol: portProtocol
                )
                let published = try await client.publishPort(machineId: machine.id, request: req)
                store.showToast(.success, "端口 \(published.port) 已暴露：\(published.url)")
                reloadAll()
                await store.refreshAll(silent: true)
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }

    private func unpublishPort(_ port: Int) {
        guard let client = store.client else { return }
        Task {
            do {
                try await client.unpublishPort(machineId: machine.id, port: port)
                store.showToast(.info, "已关闭端口 \(port) 映射")
                reloadAll()
                await store.refreshAll(silent: true)
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }
}
