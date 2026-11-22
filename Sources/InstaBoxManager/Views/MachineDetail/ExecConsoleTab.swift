import SwiftUI

struct ExecConsoleTab: View {
    @Environment(AppStore.self) private var store
    let machine: MachineItem

    @ViewState private var commandInput: String = ""
    @ViewState private var workingDirectory: String = "/data/home"
    @ViewState private var timeoutSeconds: Int = 120
    @ViewState private var outputLog: String = ""
    @ViewState private var lastExitCode: Int?
    @ViewState private var isRunningCommand = false
    @ViewState private var runningTask: Task<Void, Never>?

    @ViewState private var history: [ExecHistoryEntry] = []
    @ViewState private var isLoadingHistory = false

    private let quickCommands: [(String, String)] = [
        ("系统信息", "uname -a && cat /etc/os-release | head -n 4"),
        ("磁盘空间", "df -h"),
        ("内存负载", "free -h && uptime"),
        ("Docker 容器", "docker ps -a"),
        ("监听端口", "ss -tulpn"),
        ("Top 进程", "ps aux --sort=-%mem | head -n 15")
    ]

    var body: some View {
        LiquidSplitView(
            storageKey: "instabox.console.historyWidth",
            pinnedSide: .trailing,
            defaultWidth: 270,
            minPinnedWidth: 220,
            maxPinnedWidth: 360,
            minFlexibleWidth: 360
        ) {
            // Left: Live Streaming Console
            VStack(alignment: .leading, spacing: 11) {
                if machine.state != .running {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("当前沙盒未处于运行状态（\(machine.state.displayName)），请先启动或恢复后再执行实时命令（右侧仍可查看历史命令输出）。")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(10)
                    .glassWell(cornerRadius: 10, tint: .orange)
                }

                // Quick Preset Liquid Glass Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 6) {
                            ForEach(quickCommands, id: \.0) { label, cmd in
                                Button(label) {
                                    commandInput = cmd
                                    executeStreamingCommand()
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                                .disabled(isRunningCommand || machine.state != .running)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Working directory & Timeout row
                HStack(spacing: 10) {
                    Label("目录", systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("/data/home", text: $workingDirectory)
                        .textFieldStyle(.plain)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .glassWell(cornerRadius: 8)
                        .frame(maxWidth: 220)

                    Stepper("超时 \(timeoutSeconds)s", value: $timeoutSeconds, in: 10...600, step: 30)
                        .font(.caption)

                    Spacer()

                    if let code = lastExitCode {
                        Text("Exit: \(code)")
                            .font(.caption.monospaced().bold())
                            .contentTransition(.numericText())
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .foregroundStyle(code == 0 ? .green : .red)
                            .glassPill(tint: (code == 0 ? Color.green : Color.red).opacity(0.20))
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }

                    Button("清空输出") {
                        outputLog = ""
                        lastExitCode = nil
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }

                // Command Input Bar
                HStack(spacing: 8) {
                    Text("$")
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundStyle(Color.accentColor)
                        .padding(.leading, 4)

                    TextField("输入 bash 命令（回车立即流式执行，如 ls -la 或 python3 -V）…", text: $commandInput)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .glassWell(cornerRadius: 10)
                        .onSubmit {
                            executeStreamingCommand()
                        }
                        .disabled(isRunningCommand)

                    if isRunningCommand {
                        Button("中断", role: .destructive) {
                            runningTask?.cancel()
                            isRunningCommand = false
                        }
                        .buttonStyle(.glass)
                    } else {
                        Button("执行") {
                            executeStreamingCommand()
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || machine.state != .running)
                    }
                }

                // Terminal Output ScrollView
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(outputLog.isEmpty ? "# 输出区域（支持 SSE 实时流式 stdout / stderr）" : outputLog)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(outputLog.isEmpty ? .secondary : Color(nsColor: .textColor))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)

                            Color.clear
                                .frame(height: 1)
                                .id("BOTTOM")
                        }
                    }
                    .glassCodeCanvas(cornerRadius: 12)
                    .onChange(of: outputLog) { _, _ in
                        proxy.scrollTo("BOTTOM", anchor: .bottom)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassCard(cornerRadius: 18)
            .padding([.leading, .bottom], 12)
            .padding(.trailing, 2)
        } trailing: {
            // Right: Exec History
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 7) {
                        GlassIconOrb(systemImage: "clock.arrow.circlepath", tint: .accentColor, size: 26, iconSize: 12, cornerRadius: 8)
                        Text("命令历史记录")
                            .font(.subheadline.bold())
                    }
                    Spacer()
                    Button {
                        loadHistory()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, isActive: isLoadingHistory)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help("刷新执行历史")
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)

                if isLoadingHistory && history.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if history.isEmpty {
                    Text("暂无历史命令")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(history) { item in
                                Button {
                                    inspectHistoryEntry(item)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.command)
                                            .font(.caption.monospaced().weight(.medium))
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        HStack {
                                            Text("Exit \(item.exitCode)")
                                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(item.exitCode == 0 ? .green : .red)
                                            Text("· \(item.durationMs)ms")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(Formatters.relativeOrShortTime(item.startedAt))
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding(9)
                                    .liquidWellInteractive(cornerRadius: 10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                    .scrollEdgeEffectStyle(.soft, for: .vertical)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassCard(cornerRadius: 18)
            .padding([.trailing, .bottom], 12)
            .padding(.leading, 2)
        }
        .onAppear {
            loadHistory()
        }
    }

    private func executeStreamingCommand() {
        let cmd = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty, let client = store.client, !isRunningCommand else { return }

        isRunningCommand = true
        lastExitCode = nil
        let cwdClean = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        outputLog += (outputLog.isEmpty ? "" : "\n") + "[\(cwdClean.isEmpty ? "~" : cwdClean)]$ \(cmd)\n"

        let req = ExecRequest(
            cmd: cmd,
            cwd: cwdClean.isEmpty ? nil : cwdClean,
            timeoutSeconds: timeoutSeconds
        )

        runningTask = Task {
            do {
                try await client.streamExecCommand(machineId: machine.id, request: req) { event in
                    await MainActor.run {
                        switch event {
                        case .stdout(let chunk):
                            outputLog += chunk
                        case .stderr(let chunk):
                            outputLog += chunk
                        case .exit(let res):
                            if !res.stdout.isEmpty && !outputLog.hasSuffix(res.stdout) {
                                outputLog += res.stdout
                            }
                            if !res.stderr.isEmpty && !outputLog.hasSuffix(res.stderr) {
                                outputLog += res.stderr
                            }
                            lastExitCode = res.exitCode
                            if res.timedOut {
                                outputLog += "\n[命令执行超时]\n"
                            }
                        case .error(let detail):
                            outputLog += "\n[错误 \(detail.code)] \(detail.message)\n"
                        }
                    }
                }
                await MainActor.run {
                    isRunningCommand = false
                    loadHistory()
                }
            } catch is CancellationError {
                await MainActor.run {
                    outputLog += "\n[已取消本地流监听]\n"
                    isRunningCommand = false
                }
            } catch {
                await MainActor.run {
                    outputLog += "\n[请求异常] \(error.localizedDescription)\n"
                    isRunningCommand = false
                }
            }
        }
    }

    private func loadHistory() {
        guard let client = store.client else { return }
        isLoadingHistory = true
        Task {
            defer { isLoadingHistory = false }
            if let items = try? await client.fetchExecHistory(machineId: machine.id, limit: 40) {
                self.history = items
            }
        }
    }

    private func inspectHistoryEntry(_ item: ExecHistoryEntry) {
        guard let client = store.client else { return }
        commandInput = item.command
        Task {
            if let full = try? await client.fetchExecHistoryDetail(machineId: machine.id, execId: item.id) {
                lastExitCode = full.exitCode
                var text = "# 历史命令 (\(full.startedAt))\n$ \(full.command)\n"
                if let out = full.stdout, !out.isEmpty { text += out }
                if let err = full.stderr, !err.isEmpty { text += (text.hasSuffix("\n") ? "" : "\n") + "[stderr]\n" + err }
                outputLog = text
            }
        }
    }
}
