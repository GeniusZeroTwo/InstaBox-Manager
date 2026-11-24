import Charts
import SwiftUI

struct MetricsAndLogsTab: View {
    @Environment(AppStore.self) private var store
    let machine: MachineItem

    @ViewState private var metrics: [MachineMetric] = []
    @ViewState private var diskInfo: MachineDiskResponse?
    @ViewState private var processes: [ProcessInfoItem] = []
    @ViewState private var logsResponse: MachineLogsResponse?
    @ViewState private var processFilter: String = ""
    @ViewState private var isLoading = false

    private var filteredProcesses: [ProcessInfoItem] {
        guard !processFilter.trimmingCharacters(in: .whitespaces).isEmpty else {
            return processes
        }
        let q = processFilter.lowercased()
        return processes.filter {
            $0.command.lowercased().contains(q)
                || $0.user.lowercased().contains(q)
                || String($0.pid).contains(q)
        }
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        HStack(spacing: 8) {
                            GlassIconOrb(systemImage: "waveform.path.ecg", tint: LiquidPalette.statusBlue, size: 28, iconSize: 13, cornerRadius: 8)
                            Text("实时性能、磁盘、进程与控制台日志")
                                .font(.headline)
                                .foregroundStyle(LiquidPalette.textPrimary)
                        }
                        Spacer()
                        Button {
                            reloadAll()
                        } label: {
                            Label(isLoading ? "刷新中…" : "刷新监控", systemImage: "arrow.clockwise")
                                .symbolEffect(.rotate, isActive: isLoading)
                        }
                        .buttonStyle(.glass)
                        .disabled(isLoading)
                    }

                    chartsSection
                    diskSection
                    processesSection
                    consoleLogsSection
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

    // MARK: - Charts

    private var chartsSection: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CPU 使用率 (%)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LiquidPalette.textPrimary)
                    Spacer()
                    if let last = metrics.last {
                        Text(String(format: "%.1f%%", last.cpuUsedPct))
                            .font(.subheadline.monospacedDigit().bold())
                            .contentTransition(.numericText())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .foregroundStyle(LiquidPalette.statusGreen)
                            .glassPill(tint: LiquidPalette.statusGreen)
                            .animation(LiquidMotion.fluid, value: last.cpuUsedPct)
                    }
                }

                if metrics.isEmpty {
                    Text("暂无采样点（运行中每 30 秒采样一次）")
                        .font(.caption)
                        .foregroundStyle(LiquidPalette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 130)
                } else {
                    Chart(Array(metrics.suffix(40).enumerated()), id: \.offset) { idx, m in
                        AreaMark(
                            x: .value("Sample", idx),
                            y: .value("CPU %", m.cpuUsedPct)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [LiquidPalette.brandEmeraldSolid.color.opacity(0.36), LiquidPalette.brandEmeraldSolid.color.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Sample", idx),
                            y: .value("CPU %", m.cpuUsedPct)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.2))
                        .foregroundStyle(LiquidPalette.statusGreen)
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine().foregroundStyle(LiquidPalette.divider)
                            AxisValueLabel().foregroundStyle(LiquidPalette.textMuted)
                        }
                    }
                    .frame(height: 130)
                }
            }
            .padding(16)
            .glassCard(cornerRadius: 18, tint: LiquidPalette.statusGreen.opacity(0.05), accentTopColor: LiquidPalette.statusGreen)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("内存占用")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LiquidPalette.textPrimary)
                    Spacer()
                    if let last = metrics.last {
                        Text("\(Formatters.bytes(last.memUsed)) / \(Formatters.bytes(last.memTotal))")
                            .font(.caption.monospacedDigit().bold())
                            .contentTransition(.numericText())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .foregroundStyle(LiquidPalette.statusPurple)
                            .glassPill(tint: LiquidPalette.statusPurple)
                            .animation(LiquidMotion.fluid, value: last.memUsed)
                    }
                }

                if metrics.isEmpty {
                    Text("暂无采样点")
                        .font(.caption)
                        .foregroundStyle(LiquidPalette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 130)
                } else {
                    Chart(Array(metrics.suffix(40).enumerated()), id: \.offset) { idx, m in
                        let gib = Double(m.memUsed) / 1_073_741_824.0
                        AreaMark(
                            x: .value("Sample", idx),
                            y: .value("GiB", gib)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [LiquidPalette.statusPurple.opacity(0.32), LiquidPalette.statusPurple.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Sample", idx),
                            y: .value("GiB", gib)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(LiquidPalette.statusPurple)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine().foregroundStyle(LiquidPalette.divider)
                            AxisValueLabel().foregroundStyle(LiquidPalette.textMuted)
                        }
                    }
                    .frame(height: 130)
                }
            }
            .padding(16)
            .glassCard(cornerRadius: 18, tint: LiquidPalette.statusPurple.opacity(0.05))
        }
    }

    // MARK: - Disk Filesystems

    @ViewBuilder
    private var diskSection: some View {
        if let disk = diskInfo, !disk.filesystems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    GlassIconOrb(systemImage: "internaldrive", tint: LiquidPalette.statusTeal, size: 26, iconSize: 12, cornerRadius: 8)
                    Text("文件系统空间")
                        .font(.subheadline.bold())
                        .foregroundStyle(LiquidPalette.textPrimary)
                }

                ForEach(disk.filesystems) { fs in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(fs.mount)
                                .font(.caption.monospaced().bold())
                                .foregroundStyle(LiquidPalette.textPrimary)
                            Spacer()
                            Text("\(Formatters.bytes(fs.usedBytes)) / \(Formatters.bytes(fs.sizeBytes)) (\(String(format: "%.1f%%", fs.usedPct)))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(LiquidPalette.textSecondary)
                        }
                        LiquidProgressBar(value: fs.usedPct / 100.0, tint: LiquidPalette.statusTeal, height: 6)
                    }
                    .padding(10)
                    .glassWell(cornerRadius: 10)
                }
            }
            .padding(16)
            .glassCard(cornerRadius: 18)
        }
    }

    // MARK: - Processes

    private var processesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    GlassIconOrb(systemImage: "list.bullet.rectangle", tint: LiquidPalette.statusIndigo, size: 26, iconSize: 12, cornerRadius: 8)
                    Text("系统进程列表 (\(processes.count))")
                        .font(.subheadline.bold())
                        .foregroundStyle(LiquidPalette.textPrimary)
                }
                Spacer()
                TextField("过滤进程 / PID…", text: $processFilter)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(LiquidPalette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassWell(cornerRadius: 8)
                    .frame(width: 210)
            }

            if filteredProcesses.isEmpty {
                Text("暂无进程数据")
                    .font(.caption)
                    .foregroundStyle(LiquidPalette.textSecondary)
                    .padding(.vertical, 8)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                    GridRow {
                        Text("PID").foregroundStyle(LiquidPalette.textSecondary)
                        Text("用户").foregroundStyle(LiquidPalette.textSecondary)
                        Text("CPU%").foregroundStyle(LiquidPalette.textSecondary)
                        Text("MEM%").foregroundStyle(LiquidPalette.textSecondary)
                        Text("命令").foregroundStyle(LiquidPalette.textSecondary)
                        Text("操作").foregroundStyle(LiquidPalette.textSecondary)
                    }
                    .font(.caption2.bold())

                    Rectangle()
                        .fill(LiquidPalette.divider)
                        .frame(height: 1)
                        .gridCellUnsizedAxes([.horizontal])

                    ForEach(filteredProcesses.prefix(25)) { proc in
                        GridRow {
                            Text("\(proc.pid)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(LiquidPalette.textPrimary)
                            Text(proc.user)
                                .font(.caption)
                                .foregroundStyle(LiquidPalette.textSecondary)
                            Text(String(format: "%.1f", proc.cpuPercent))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(LiquidPalette.textPrimary)
                            Text(String(format: "%.1f", proc.memPercent))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(LiquidPalette.textPrimary)
                            Text(proc.command)
                                .font(.caption.monospaced())
                                .foregroundStyle(LiquidPalette.textPrimary)
                                .lineLimit(1)
                            if machine.state == .running && proc.pid > 1 {
                                Button("结束") {
                                    killProcess(proc.pid)
                                }
                                .buttonStyle(.glass)
                                .controlSize(.mini)
                                .foregroundStyle(LiquidPalette.statusRed)
                            } else {
                                Text("—").font(.caption2).foregroundStyle(LiquidPalette.textMuted)
                            }
                        }
                    }
                }
                .padding(10)
                .glassWell(cornerRadius: 11)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 18)
    }

    // MARK: - Console & Operation Logs

    private var consoleLogsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    GlassIconOrb(systemImage: "apple.terminal.on.rectangle", tint: LiquidPalette.statusOrange, size: 26, iconSize: 12, cornerRadius: 8)
                    Text("内核与控制台启动日志 (Console Logs)")
                        .font(.subheadline.bold())
                        .foregroundStyle(LiquidPalette.textPrimary)
                }
                Spacer()
                if let logText = logsResponse?.console, !logText.isEmpty {
                    Button("复制日志") {
                        TerminalLauncher.copyToClipboard(logText)
                        store.showToast(.info, "已复制控制台日志")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }

            ScrollView {
                let hasLogs = logsResponse?.console.isEmpty == false
                Text(hasLogs ? logsResponse!.console : "暂无控制台日志输出")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(hasLogs ? LiquidPalette.textPrimary : LiquidPalette.textMuted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(height: 220)
            .glassCodeCanvas(cornerRadius: 11)

            if let ops = logsResponse?.operations, !ops.isEmpty {
                Text("最近生命周期变更记录")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiquidPalette.textSecondary)
                    .padding(.top, 4)

                ForEach(ops.prefix(8)) { op in
                    HStack {
                        Text(op.type.uppercased())
                            .font(.caption2.monospaced().bold())
                            .foregroundStyle(LiquidPalette.textPrimary)
                            .frame(width: 68, alignment: .leading)
                        Text(op.state)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(op.state == "succeeded" ? LiquidPalette.statusGreen : (op.state == "failed" ? LiquidPalette.statusRed : LiquidPalette.statusOrange))
                        if let trigger = op.trigger {
                            Text("(\(trigger))")
                                .font(.caption2)
                                .foregroundStyle(LiquidPalette.textSecondary)
                        }
                        if let err = op.error {
                            Text(err.message)
                                .font(.caption2)
                                .foregroundStyle(LiquidPalette.statusRed)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(Formatters.relativeOrShortTime(op.createdAt))
                            .font(.caption2)
                            .foregroundStyle(LiquidPalette.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassWell(cornerRadius: 8)
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 18)
    }

    private func reloadAll() {
        guard let client = store.client else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            async let mTask = try? client.fetchMachineMetrics(machineId: machine.id)
            async let dTask = try? client.fetchMachineDisk(machineId: machine.id)
            async let pTask = try? client.fetchMachineProcesses(machineId: machine.id, all: true)
            async let lTask = try? client.fetchMachineLogs(machineId: machine.id, tail: 300)

            if let m = await mTask {
                self.metrics = m.metrics
                if let d = m.disk { self.diskInfo = d }
            }
            if let d = await dTask { self.diskInfo = d }
            if let p = await pTask { self.processes = p.processes }
            if let l = await lTask { self.logsResponse = l }
        }
    }

    private func killProcess(_ pid: Int) {
        guard let client = store.client else { return }
        Task {
            do {
                _ = try await client.execCommand(
                    machineId: machine.id,
                    request: ExecRequest(argv: ["kill", "-9", String(pid)], noHistory: true)
                )
                store.showToast(.info, "已向 PID \(pid) 发送 SIGKILL")
                reloadAll()
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }
}
