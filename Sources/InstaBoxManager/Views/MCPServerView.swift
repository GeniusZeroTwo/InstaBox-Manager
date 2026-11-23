import AppKit
import SwiftUI

private enum MCPClientPreset: String, CaseIterable, Identifiable, Sendable {
    case claudeDesktop = "Claude Desktop"
    case cursor = "Cursor"
    case httpGeneric = "HTTP / Antigravity"
    case claudeCode = "Claude Code CLI"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .claudeDesktop: return "sparkles"
        case .cursor: return "cursorarrow.rays"
        case .httpGeneric: return "globe"
        case .claudeCode: return "terminal"
        }
    }
}

struct MCPServerView: View {
    @Environment(AppStore.self) private var store

    @ViewState private var selectedPreset: MCPClientPreset = .claudeDesktop
    @ViewState private var includeAPIKeyInConfig: Bool = false
    @ViewState private var portInput: String = "28765"

    // Playground
    @ViewState private var selectedToolName: String = "instabox_list_machines"
    @ViewState private var toolArgumentsJSON: String = "{}"
    @ViewState private var playgroundOutput: String = ""
    @ViewState private var isRunningPlayground = false
    @ViewState private var showAllTools = false

    private var presetSegments: [LiquidGlassSegmentItem<MCPClientPreset>] {
        MCPClientPreset.allCases.map {
            LiquidGlassSegmentItem(value: $0, title: $0.rawValue, icon: $0.icon)
        }
    }

    var body: some View {
        @Bindable var bindableStore = store

        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 20) {
                    serverHeroCard
                        .liquidAppear(delay: 0.0)
                    clientIntegrationCard
                        .liquidAppear(delay: 0.05)
                    playgroundCard
                        .liquidAppear(delay: 0.10)
                    toolsAndResourcesCatalogCard
                        .liquidAppear(delay: 0.14)
                    activityLogsCard
                        .liquidAppear(delay: 0.18)
                }
                .padding(24)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .navigationTitle("MCP 服务")
        .onAppear {
            portInput = String(store.mcpServerPort)
        }
    }

    // MARK: - Server Control Hero Card

    private var serverHeroCard: some View {
        @Bindable var bindableStore = store

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                GlassIconOrb(
                    systemImage: "point.3.connected.trianglepath.dotted",
                    tint: store.mcpServerRunning ? .green : .accentColor,
                    size: 46,
                    iconSize: 20,
                    cornerRadius: 14
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("InstaBox 原生 MCP 服务器")
                            .font(.title2.weight(.semibold))
                        HStack(spacing: 6) {
                            LivePulseDot(
                                color: store.mcpServerRunning ? .green : .secondary,
                                isPulsing: store.mcpServerRunning,
                                size: 7
                            )
                            Text(store.mcpServerRunning ? "HTTP 运行中" : "HTTP 未启动")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .foregroundStyle(store.mcpServerRunning ? .green : .secondary)
                        .glassPill(tint: store.mcpServerRunning ? .green.opacity(0.20) : nil)

                        Text("Stdio 随时可用")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .foregroundStyle(.blue)
                            .glassPill(tint: .blue.opacity(0.18))
                    }

                    Text("让 Claude Desktop、Cursor、Antigravity、Claude Code 等 AI Agent 直接操控你的 InstaBox 云端沙盒（内置 \(MCPServerEngine.toolCatalog.count) 个工具与 4 个实时资源）。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if store.mcpServerRunning {
                    Button {
                        store.stopMCPServer()
                    } label: {
                        Label("停止 HTTP 服务", systemImage: "stop.fill")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                } else {
                    Button {
                        applyPortAndStart()
                    } label: {
                        Label("启动 HTTP 服务", systemImage: "play.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.green)
                    .controlSize(.large)
                }
            }

            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    Text("本地监听地址")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("http://127.0.0.1:")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    TextField("28765", text: $portInput)
                        .textFieldStyle(.plain)
                        .font(.caption.monospaced().bold())
                        .frame(width: 58)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassWell(cornerRadius: 7)
                        .disabled(store.mcpServerRunning)
                    Text("/mcp")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Button {
                        TerminalLauncher.copyToClipboard(store.mcpHTTPEndpoint)
                        store.showToast(.success, "已复制 HTTP MCP 地址")
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.mini)
                    .help("复制 Streamable HTTP MCP 地址")
                }

                Spacer()

                Toggle("应用启动时自动开启本地 HTTP MCP", isOn: $bindableStore.mcpAutoStart)
                    .font(.caption)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassWell(cornerRadius: 12)

            HStack(spacing: 10) {
                Label("Stdio 启动命令", systemImage: "terminal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\"\(store.mcpExecutablePath)\" --mcp")
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button("复制命令") {
                    TerminalLauncher.copyToClipboard("\"\(store.mcpExecutablePath)\" --mcp")
                    store.showToast(.success, "Stdio 启动命令已复制")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassWell(cornerRadius: 12)

            if let err = store.mcpServerError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(10)
                .glassWell(cornerRadius: 10, tint: .red)
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 22, tint: (store.mcpServerRunning ? Color.green : Color.accentColor).opacity(0.05))
    }

    // MARK: - AI Client Integration & One-Click Install Card

    private var clientIntegrationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 9) {
                    GlassIconOrb(systemImage: "wand.and.stars", tint: .indigo, size: 30, iconSize: 14, cornerRadius: 9)
                    Text("AI 客户端一键配置")
                        .font(.headline)
                }
                Spacer()
                Toggle("写入明文 API Key（关闭则自动安全复用本应用钥匙串）", isOn: $includeAPIKeyInConfig)
                    .font(.caption)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LiquidGlassSegmentedPicker(items: presetSegments, selection: $selectedPreset)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(configSnippet(for: selectedPreset))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .glassCodeCanvas(cornerRadius: 12)

            HStack(spacing: 10) {
                Text(configHint(for: selectedPreset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                Button {
                    TerminalLauncher.copyToClipboard(configSnippet(for: selectedPreset))
                    store.showToast(.success, "已复制 \(selectedPreset.rawValue) MCP 配置")
                } label: {
                    Label("复制配置", systemImage: "doc.on.doc")
                }
                .buttonStyle(.glass)

                if selectedPreset == .claudeDesktop || selectedPreset == .cursor {
                    Button {
                        installConfigFile(for: selectedPreset)
                    } label: {
                        Label("一键写入配置文件", systemImage: "square.and.arrow.down.on.square")
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 20)
    }

    // MARK: - Interactive MCP Playground

    private var playgroundCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 9) {
                    GlassIconOrb(systemImage: "play.rectangle.on.rectangle", tint: .blue, size: 30, iconSize: 14, cornerRadius: 9)
                    Text("MCP 工具在线调试器 (JSON-RPC Playground)")
                        .font(.headline)
                }
                Spacer()
                Button {
                    runPlayground()
                } label: {
                    HStack(spacing: 6) {
                        if isRunningPlayground {
                            ProgressView().controlSize(.mini)
                        }
                        Label(isRunningPlayground ? "调用中…" : "执行 tools/call", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(isRunningPlayground)
            }

            HStack(spacing: 10) {
                Picker("选择 MCP 工具", selection: $selectedToolName) {
                    ForEach(MCPServerEngine.toolCatalog) { item in
                        Text("\(item.name) — \(item.summary)").tag(item.name)
                    }
                }
                .onChange(of: selectedToolName) { _, newTool in
                    toolArgumentsJSON = defaultArgumentsTemplate(for: newTool)
                }

                Button("填充示例参数") {
                    toolArgumentsJSON = defaultArgumentsTemplate(for: selectedToolName)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("请求参数 (JSON Object)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $toolArgumentsJSON)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(height: 150)
                        .glassCodeCanvas(cornerRadius: 11)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("JSON-RPC 2.0 响应结果")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !playgroundOutput.isEmpty {
                            Button("复制响应") {
                                TerminalLauncher.copyToClipboard(playgroundOutput)
                                store.showToast(.success, "响应内容已复制")
                            }
                            .buttonStyle(.glass)
                            .controlSize(.mini)
                        }
                    }
                    ScrollView {
                        Text(playgroundOutput.isEmpty ? "# 点击右上角「执行 tools/call」即时验证 MCP 工具调用" : playgroundOutput)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(playgroundOutput.isEmpty ? .secondary : Color(nsColor: .textColor))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(height: 150)
                    .glassCodeCanvas(cornerRadius: 11)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 20)
    }

    // MARK: - Tools & Resources Catalog

    private var toolsAndResourcesCatalogCard: some View {
        let visibleTools = showAllTools ? MCPServerEngine.toolCatalog : Array(MCPServerEngine.toolCatalog.prefix(8))

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 9) {
                    GlassIconOrb(systemImage: "wrench.and.screwdriver.fill", tint: .purple, size: 30, iconSize: 14, cornerRadius: 9)
                    Text("已暴露 MCP 工具与资源 (\(MCPServerEngine.toolCatalog.count) Tools · 4 Resources)")
                        .font(.headline)
                }
                Spacer()
                Button(showAllTools ? "收起列表" : "展开全部 \(MCPServerEngine.toolCatalog.count) 个工具") {
                    withAnimation(LiquidMotion.fluid) {
                        showAllTools.toggle()
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 10)], spacing: 10) {
                ForEach(visibleTools) { tool in
                    Button {
                        selectedToolName = tool.name
                        toolArgumentsJSON = defaultArgumentsTemplate(for: tool.name)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(tool.name)
                                    .font(.caption.monospaced().bold())
                                    .lineLimit(1)
                                Spacer()
                                Text(tool.category)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .foregroundStyle(.secondary)
                                    .glassPill()
                            }
                            Text(tool.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text("参数：\(tool.parametersSummary)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .liquidWellInteractive(cornerRadius: 11)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Text("MCP Resources:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(["instabox://workspace/usage", "instabox://machines", "instabox://snapshots", "instabox://ports"], id: \.self) { uri in
                    Text(uri)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassPill(tint: .purple.opacity(0.14))
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 20)
    }

    // MARK: - Live Activity Logs

    private var activityLogsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 9) {
                    GlassIconOrb(systemImage: "waveform.path.ecg.rectangle", tint: .teal, size: 30, iconSize: 14, cornerRadius: 9)
                    Text("实时 MCP 调用日志 (\(store.mcpLogs.count))")
                        .font(.headline)
                }
                Spacer()
                if !store.mcpLogs.isEmpty {
                    Button("清空日志") {
                        store.clearMCPLogs()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }

            if store.mcpLogs.isEmpty {
                Text("暂无调用记录。启动本地 HTTP MCP 服务或使用上方调试器测试调用后，请求耗时与状态将实时显示在此处。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(18)
                    .glassWell(cornerRadius: 12)
            } else {
                VStack(spacing: 7) {
                    ForEach(store.mcpLogs.prefix(25)) { log in
                        HStack(alignment: .top, spacing: 10) {
                            Text(log.transport)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .foregroundStyle(log.transport == "HTTP" ? .green : .blue)
                                .glassPill(tint: (log.transport == "HTTP" ? Color.green : Color.blue).opacity(0.18))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(log.method)
                                        .font(.caption.monospaced().bold())
                                    Text(log.detail)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Text(log.responsePreview)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(log.isError ? .red : .secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(log.isError ? "ERROR" : "\(log.durationMs) ms")
                                    .font(.caption2.monospacedDigit().bold())
                                    .foregroundStyle(log.isError ? .red : .green)
                                Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(10)
                        .glassWell(cornerRadius: 10, tint: log.isError ? .red : nil)
                    }
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 20)
    }

    // MARK: - Helpers

    private func applyPortAndStart() {
        if let p = Int(portInput.trimmingCharacters(in: .whitespacesAndNewlines)), (1024...65535).contains(p) {
            store.mcpServerPort = p
        } else {
            portInput = String(store.mcpServerPort)
        }
        store.startMCPServer()
    }

    private func runPlayground() {
        isRunningPlayground = true
        let tool = selectedToolName
        let args = toolArgumentsJSON
        Task {
            let out = await store.runMCPPlayground(toolName: tool, argumentsJSON: args)
            playgroundOutput = out
            isRunningPlayground = false
        }
    }

    private func defaultArgumentsTemplate(for toolName: String) -> String {
        let sampleMachine = store.selectedMachineID ?? store.machines.first?.id ?? "m_replace_with_id"
        switch toolName {
        case "instabox_get_usage", "instabox_list_snapshots":
            return "{}"
        case "instabox_list_machines":
            return "{\n  \"state\": \"running\"\n}"
        case "instabox_get_machine":
            return "{\n  \"machine_id\": \"\(sampleMachine)\"\n}"
        case "instabox_create_machine":
            return "{\n  \"name\": \"mcp-sandbox\",\n  \"template_id\": \"agent-browser\",\n  \"wait_ready\": true\n}"
        case "instabox_machine_lifecycle":
            return "{\n  \"machine_id\": \"\(sampleMachine)\",\n  \"action\": \"wake\"\n}"
        case "instabox_exec_command":
            return "{\n  \"machine_id\": \"\(sampleMachine)\",\n  \"cmd\": \"uname -a && ls -la /data/home\",\n  \"cwd\": \"/data/home\"\n}"
        case "instabox_list_files":
            return "{\n  \"machine_id\": \"\(sampleMachine)\",\n  \"path\": \"/data/home\"\n}"
        case "instabox_read_file":
            return "{\n  \"machine_id\": \"\(sampleMachine)\",\n  \"path\": \"/etc/os-release\"\n}"
        case "instabox_write_file":
            return "{\n  \"machine_id\": \"\(sampleMachine)\",\n  \"path\": \"/data/home/hello-mcp.txt\",\n  \"content\": \"Hello from InstaBox MCP!\\n\"\n}"
        case "instabox_create_snapshot":
            return "{\n  \"machine_id\": \"\(sampleMachine)\",\n  \"name\": \"mcp-snap-\(Int(Date().timeIntervalSince1970))\"\n}"
        case "instabox_restore_snapshot":
            return "{\n  \"machine_id\": \"\(sampleMachine)\",\n  \"snapshot_id\": \"snap_replace_with_id\"\n}"
        case "instabox_list_ports":
            return "{\n  \"machine_id\": \"\(sampleMachine)\"\n}"
        case "instabox_publish_port":
            return "{\n  \"machine_id\": \"\(sampleMachine)\",\n  \"port\": 3000,\n  \"access\": \"public\",\n  \"protocol\": \"http\"\n}"
        case "instabox_unpublish_port":
            return "{\n  \"machine_id\": \"\(sampleMachine)\",\n  \"port\": 3000\n}"
        case "instabox_create_ssh_token":
            return "{\n  \"machine_id\": \"\(sampleMachine)\",\n  \"name\": \"mcp-agent\",\n  \"ttl_seconds\": 3600\n}"
        case "instabox_machine_diagnostics":
            return "{\n  \"machine_id\": \"\(sampleMachine)\",\n  \"tail\": 60\n}"
        case "instabox_clipboard_sync":
            return "{\n  \"machine_id\": \"\(sampleMachine)\",\n  \"direction\": \"pull\"\n}"
        default:
            return "{}"
        }
    }

    private func serverEntryDictionary(for preset: MCPClientPreset) -> [String: Any] {
        if preset == .httpGeneric {
            return [
                "url": store.mcpHTTPEndpoint
            ]
        }
        var entry: [String: Any] = [
            "command": store.mcpExecutablePath,
            "args": ["--mcp"]
        ]
        if includeAPIKeyInConfig, let key = store.activeRawAPIKeyForMCPConfig, !key.isEmpty {
            var envDict: [String: String] = ["INSTABOX_API_KEY": key]
            if let base = store.activeProfile?.normalizedBaseURL, base != "https://api.instabox.sh" {
                envDict["INSTABOX_BASE_URL"] = base
            }
            entry["env"] = envDict
        }
        return entry
    }

    private func configSnippet(for preset: MCPClientPreset) -> String {
        if preset == .claudeCode {
            if includeAPIKeyInConfig, let key = store.activeRawAPIKeyForMCPConfig, !key.isEmpty {
                return "claude mcp add instabox -e INSTABOX_API_KEY=\(key) -- \"\(store.mcpExecutablePath)\" --mcp"
            }
            return "claude mcp add instabox -- \"\(store.mcpExecutablePath)\" --mcp"
        }

        let root: [String: Any] = [
            "mcpServers": [
                "instabox": serverEntryDictionary(for: preset)
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    private func configHint(for preset: MCPClientPreset) -> String {
        switch preset {
        case .claudeDesktop:
            return "目标文件：~/Library/Application Support/Claude/claude_desktop_config.json"
        case .cursor:
            return "目标文件：~/.cursor/mcp.json"
        case .httpGeneric:
            return "使用 Streamable HTTP 端点（需保持上方本地 HTTP 服务处于运行状态），仅监听 127.0.0.1 本机回环"
        case .claudeCode:
            return "在终端直接运行上述命令即可将 InstaBox 注册为 Claude Code 的 MCP 工具集"
        }
    }

    private func installConfigFile(for preset: MCPClientPreset) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let targetURL: URL
        switch preset {
        case .claudeDesktop:
            targetURL = home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        case .cursor:
            targetURL = home.appendingPathComponent(".cursor/mcp.json")
        default:
            return
        }

        do {
            try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var root: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: targetURL.path),
               let existingData = try? Data(contentsOf: targetURL),
               !existingData.isEmpty {
                guard let parsed = try JSONSerialization.jsonObject(with: existingData) as? [String: Any] else {
                    store.showToast(.error, "现有配置文件不是标准 JSON 对象，请手动复制合并。")
                    return
                }
                root = parsed
            }
            var servers = root["mcpServers"] as? [String: Any] ?? [:]
            servers["instabox"] = serverEntryDictionary(for: preset)
            root["mcpServers"] = servers

            let outData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try outData.write(to: targetURL, options: .atomic)
            store.showToast(.success, "已自动写入 \(preset.rawValue) 配置（重启客户端即生效）")
        } catch {
            store.showToast(.error, "写入配置失败：\(error.localizedDescription)")
        }
    }
}
