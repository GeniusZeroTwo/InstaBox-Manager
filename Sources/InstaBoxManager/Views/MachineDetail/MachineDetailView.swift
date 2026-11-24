import SwiftUI

enum MachineInspectorTab: String, CaseIterable, Identifiable, Sendable {
    case overview = "概览配置"
    case terminal = "命令终端"
    case files = "文件管理"
    case sshAndPorts = "SSH 与端口"
    case desktop = "远程桌面"
    case metricsAndLogs = "监控与日志"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "slider.horizontal.3"
        case .terminal: return "apple.terminal"
        case .files: return "folder"
        case .sshAndPorts: return "network"
        case .desktop: return "display"
        case .metricsAndLogs: return "chart.xyaxis.line"
        }
    }
}

struct MachineDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let machine: MachineItem

    @ViewState private var selectedTab: MachineInspectorTab = .overview
    @ViewState private var tabSlideDirection: CGFloat = 1
    @ViewState private var showSaveSnapshotSheet = false
    @ViewState private var snapshotName = ""
    @ViewState private var snapshotDesc = ""
    @ViewState private var isSavingSnapshot = false
    @ViewState private var confirmDelete = false

    // Overview edit states
    @ViewState private var editedName: String = ""
    @ViewState private var editedDiskGiB: Int = 20
    @ViewState private var selectedSpecIdx: Int = 0
    @ViewState private var editedIdleMinutes: Int = 30
    @ViewState private var applyWithRestart: Bool = false
    @ViewState private var selectedRestoreSnapshotId: String = ""
    @ViewState private var isUpdatingConfig = false

    private var activeOp: OperationItem? {
        store.activeOperations[machine.id]
    }

    private var inspectorSegments: [LiquidGlassSegmentItem<MachineInspectorTab>] {
        MachineInspectorTab.allCases.map {
            LiquidGlassSegmentItem(value: $0, title: $0.rawValue, icon: $0.icon)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Unified Floating Liquid Glass Command Deck
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 8) {
                    machineHeaderBar
                    tabSelectorBar
                }
            }
            .padding([.horizontal, .top], 12)

            ZStack {
                switch selectedTab {
                case .overview:
                    overviewTabContent
                        .transition(tabContentTransition)
                case .terminal:
                    ExecConsoleTab(machine: machine)
                        .transition(tabContentTransition)
                case .files:
                    FileBrowserTab(machine: machine)
                        .transition(tabContentTransition)
                case .sshAndPorts:
                    SSHAndPortsTab(machine: machine)
                        .transition(tabContentTransition)
                case .desktop:
                    RemoteDesktopTab(machine: machine)
                        .transition(tabContentTransition)
                case .metricsAndLogs:
                    MetricsAndLogsTab(machine: machine)
                        .transition(tabContentTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(reduceMotion ? nil : LiquidMotion.fluid, value: selectedTab)
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            let all = MachineInspectorTab.allCases
            if let oldIdx = all.firstIndex(of: oldTab), let newIdx = all.firstIndex(of: newTab) {
                tabSlideDirection = newIdx >= oldIdx ? 1 : -1
            }
        }
        .onAppear {
            syncEditStates()
        }
        .onChange(of: machine.updatedAt) { _, _ in
            syncEditStates()
        }
        .sheet(isPresented: $showSaveSnapshotSheet) {
            saveSnapshotModal
        }
        .confirmationDialog("确认永久删除沙盒「\(machine.name)」？", isPresented: $confirmDelete) {
            Button("永久删除", role: .destructive) {
                Task { await store.deleteMachine(machine) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("该操作将不可恢复地移除沙盒 \(machine.id) 及其系统与持久化数据。")
        }
    }

    private func syncEditStates() {
        editedName = machine.name
        editedDiskGiB = machine.storage?.sizeGiB ?? machine.spec.persistentDiskGiB ?? 20
        if let idx = store.allowedSpecs.firstIndex(where: { $0.vcpus == machine.spec.vcpus && $0.memMiB == machine.spec.memMiB }) {
            selectedSpecIdx = idx
        }
        if let secs = machine.autoSuspendAfterSeconds {
            editedIdleMinutes = secs == 0 ? 0 : max(5, secs / 60)
        } else {
            editedIdleMinutes = 30
        }
        if selectedRestoreSnapshotId.isEmpty, let firstSnap = store.snapshots.first(where: { $0.status == "ready" }) {
            selectedRestoreSnapshotId = firstSnap.id
        }
    }

    // MARK: - Top Header Island

    private var machineHeaderBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(machine.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(LiquidPalette.textPrimary)
                        .lineLimit(1)
                        .help(machine.name)
                    StateBadge(state: machine.state, operation: activeOp)
                    if machine.runtime?.ready == true && machine.state == .running {
                        Text("Ready")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .foregroundStyle(LiquidPalette.statusGreen)
                            .glassPill(tint: LiquidPalette.statusGreen)
                    }
                }
                HStack(spacing: 8) {
                    Button {
                        TerminalLauncher.copyToClipboard(machine.id)
                        store.showToast(.info, "已复制 ID：\(machine.id)")
                    } label: {
                        Label(machine.id, systemImage: "doc.on.doc")
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LiquidPalette.textSecondary)
                    .help("点击复制实例 ID：\(machine.id)")

                    Text("· \(machine.template.id)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(LiquidPalette.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Text("· \(machine.spec.displayLabel)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(LiquidPalette.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            // Primary Lifecycle Glass Buttons
            HStack(spacing: 8) {
                if machine.state == .stopped {
                    Button {
                        Task { await store.startMachine(machine) }
                    } label: {
                        Label("启动", systemImage: "play.fill")
                    }
                    .buttonStyle(.emeraldPrimary)
                    .disabled(activeOp != nil)
                }

                if machine.state == .suspended {
                    Button {
                        Task { await store.resumeMachine(machine) }
                    } label: {
                        Label("恢复", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(LiquidPalette.prominentIndigo.color)
                    .disabled(activeOp != nil)
                }

                if machine.state == .running {
                    Button {
                        Task { await store.openQuickSSH(for: machine) }
                    } label: {
                        Label("SSH 终端", systemImage: "terminal")
                            .lineLimit(1)
                    }
                    .buttonStyle(.emeraldPrimary)

                    Button {
                        Task { await store.suspendMachine(machine) }
                    } label: {
                        Label("暂停", systemImage: "pause.fill")
                            .lineLimit(1)
                    }
                    .buttonStyle(.glass)
                    .disabled(activeOp != nil)

                    Button {
                        Task { await store.stopMachine(machine) }
                    } label: {
                        Label("关机", systemImage: "stop.fill")
                            .lineLimit(1)
                    }
                    .buttonStyle(.glass)
                    .disabled(activeOp != nil)
                }

                Menu {
                    Button {
                        Task { await store.restartMachine(machine) }
                    } label: {
                        Label("重启沙盒 (Restart)", systemImage: "arrow.clockwise")
                    }

                    Button {
                        snapshotName = "\(machine.name)-\(Int(Date().timeIntervalSince1970))"
                        snapshotDesc = ""
                        showSaveSnapshotSheet = true
                    } label: {
                        Label("保存为快照…", systemImage: "camera.aperture")
                    }

                    Button {
                        Task { await store.forkMachine(machine, newName: "\(machine.name)-fork") }
                    } label: {
                        Label("快速克隆 (Fork)", systemImage: "plus.square.on.square")
                    }

                    Divider()

                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("永久删除沙盒…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                }
                .buttonStyle(.glass)
                .help("更多沙盒操作")
                .accessibilityLabel("更多沙盒操作")
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .glassCard(cornerRadius: 18)
    }

    private var tabSelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LiquidGlassSegmentedPicker(
                items: inspectorSegments,
                selection: $selectedTab
            )
        }
    }

    // MARK: - Overview & Config Tab

    private var overviewTabContent: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    if let err = machine.lastError {
                        alertCard(
                            title: "最近一次错误 (\(err.code))",
                            body: err.message,
                            color: LiquidPalette.statusRed,
                            icon: "exclamationmark.octagon.fill"
                        )
                    }

                    if let lock = machine.abuseLock {
                        alertCard(
                            title: "安全风控暂停提示",
                            body: "\(lock.explanation)\n详情：\(lock.what)\n申诉方式：\(lock.appeal)",
                            color: LiquidPalette.statusOrange,
                            icon: "shield.lefthalf.filled.trianglebadge.exclamationmark"
                        )
                    }

                    if let oom = machine.lastOom {
                        alertCard(
                            title: "检测到内核 OOM Kill（累计 \(machine.oomKills ?? 1) 次）",
                            body: "进程 \(oom.process) (PID \(oom.pid)) 占用内存 \(Formatters.bytes(oom.rssBytes)) 时被终止，时间：\(Formatters.relativeOrShortTime(oom.at))",
                            color: LiquidPalette.statusOrange,
                            icon: "memorychip"
                        )
                    }

                    // System & Spec Details
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            GlassIconOrb(systemImage: "cpu", tint: LiquidPalette.statusBlue, size: 28, iconSize: 13, cornerRadius: 8)
                            Text("实例属性")
                                .font(.headline)
                                .foregroundStyle(LiquidPalette.textPrimary)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 10) {
                            kvCell("实例 ID", machine.id)
                            kvCell("默认登录用户", machine.guestUser)
                            kvCell("CPU / 内存", machine.spec.displayLabel)
                            kvCell("持久化磁盘", "\(machine.storage?.sizeGiB ?? machine.spec.persistentDiskGiB ?? 20) GiB (\(machine.storage?.mountPath ?? "/data"))")
                            kvCell("磁盘同步状态", machine.storage?.synced == false ? "同步落盘中…" : "已同步")
                            kvCell("系统模板", "\(machine.template.id) (\(machine.template.version))")
                            kvCell("空闲自动暂停", machine.autoSuspendAfterSeconds == 0 ? "已关闭 (Always On)" : "\((machine.autoSuspendAfterSeconds ?? 1800) / 60) 分钟")
                            kvCell("单次最大运行", (machine.maxRunMinutes ?? -1) < 0 ? "无限制" : "\(machine.maxRunMinutes ?? 0) 分钟")
                            kvCell("创建时间", Formatters.relativeOrShortTime(machine.createdAt))
                            kvCell("最近更新", Formatters.relativeOrShortTime(machine.updatedAt))
                        }
                    }
                    .padding(18)
                    .glassCard(cornerRadius: 18)

                    // Edit / Resize Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            GlassIconOrb(systemImage: "slider.horizontal.3", tint: LiquidPalette.statusIndigo, size: 28, iconSize: 13, cornerRadius: 8)
                            Text("修改名称、规格扩容与自动暂停")
                                .font(.headline)
                                .foregroundStyle(LiquidPalette.textPrimary)
                        }

                        HStack(spacing: 12) {
                            TextField("沙盒名称", text: $editedName)
                                .textFieldStyle(.plain)
                                .foregroundStyle(LiquidPalette.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .glassWell(cornerRadius: 9)
                                .frame(maxWidth: 280)

                            Button("保存重命名") {
                                patchMachine(UpdateMachineRequest(name: editedName.trimmingCharacters(in: .whitespacesAndNewlines)))
                            }
                            .buttonStyle(.glass)
                            .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editedName == machine.name || isUpdatingConfig)
                        }

                        let specs = store.allowedSpecs
                        HStack(spacing: 16) {
                            Picker("机型规格", selection: $selectedSpecIdx) {
                                ForEach(Array(specs.enumerated()), id: \.offset) { idx, sp in
                                    Text(sp.displayLabel).tag(idx)
                                }
                            }
                            .frame(maxWidth: 280)
                            .disabled(specs.count <= 1)

                            Stepper("数据盘 (/data)：\(editedDiskGiB) GiB", value: $editedDiskGiB, in: 1...1024, step: 5)
                                .foregroundStyle(LiquidPalette.textPrimary)
                                .frame(maxWidth: 240)
                        }

                        HStack(spacing: 16) {
                            Picker("空闲自动暂停", selection: $editedIdleMinutes) {
                                Text("5 分钟").tag(5)
                                Text("10 分钟").tag(10)
                                Text("15 分钟").tag(15)
                                Text("20 分钟").tag(20)
                                Text("30 分钟").tag(30)
                                Text("关闭 (Always On)").tag(0)
                            }
                            .frame(maxWidth: 240)

                            Toggle("运行中自动重启生效", isOn: $applyWithRestart)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(LiquidPalette.textSecondary)

                            Spacer(minLength: 8)

                            Button("应用规格与策略变更") {
                                let chosen = specs.indices.contains(selectedSpecIdx) ? specs[selectedSpecIdx] : nil
                                var req = UpdateMachineRequest()
                                if let chosen, (chosen.vcpus != machine.spec.vcpus || chosen.memMiB != machine.spec.memMiB) {
                                    req.vcpus = chosen.vcpus
                                    req.memMiB = chosen.memMiB
                                }
                                let currentDisk = machine.storage?.sizeGiB ?? machine.spec.persistentDiskGiB ?? 20
                                if editedDiskGiB != currentDisk {
                                    req.persistentDiskGiB = editedDiskGiB
                                }
                                let targetIdleSecs = editedIdleMinutes == 0 ? 0 : editedIdleMinutes * 60
                                if targetIdleSecs != (machine.autoSuspendAfterSeconds ?? 1800) {
                                    req.autoSuspendAfterSeconds = targetIdleSecs
                                }
                                if applyWithRestart && machine.state != .stopped {
                                    req.apply = "restart"
                                }
                                patchMachine(req)
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(isUpdatingConfig)
                        }

                        Text("说明：免费套餐固定为 4 vCPU / 8 GiB / 20 GiB 磁盘及 30 分钟空闲暂停；付费套餐支持在线扩容 /data 磁盘或在停止/重启时调整规格。")
                            .font(.caption)
                            .foregroundStyle(LiquidPalette.textMuted)
                    }
                    .padding(18)
                    .glassCard(cornerRadius: 18)

                    // In-place Restore from Snapshot
                    let readySnaps = store.snapshots.filter { $0.status == "ready" }
                    if !readySnaps.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                GlassIconOrb(systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90", tint: LiquidPalette.statusPurple, size: 28, iconSize: 13, cornerRadius: 8)
                                Text("从快照原地还原 (In-Place Restore)")
                                    .font(.headline)
                                    .foregroundStyle(LiquidPalette.textPrimary)
                            }
                            Text("保留当前沙盒 ID、名称与公网端口 URL，将磁盘内容回滚到所选快照。")
                                .font(.caption)
                                .foregroundStyle(LiquidPalette.textSecondary)

                            HStack(spacing: 12) {
                                Picker("目标快照", selection: $selectedRestoreSnapshotId) {
                                    ForEach(readySnaps) { snap in
                                        Text("\(snap.name) (\(snap.id))").tag(snap.id)
                                    }
                                }
                                .frame(maxWidth: 360)

                                Button("原地还原到此快照") {
                                    restoreFromSnapshot()
                                }
                                .buttonStyle(.glass)
                                .disabled(selectedRestoreSnapshotId.isEmpty || activeOp != nil)
                            }
                        }
                        .padding(18)
                        .glassCard(cornerRadius: 18)
                    }

                    // Metadata & Env Names
                    if (machine.metadata?.isEmpty == false) || (machine.envNames?.isEmpty == false) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                GlassIconOrb(systemImage: "tag", tint: LiquidPalette.statusTeal, size: 28, iconSize: 13, cornerRadius: 8)
                                Text("标签 (Metadata) 与注入变量名")
                                    .font(.headline)
                                    .foregroundStyle(LiquidPalette.textPrimary)
                            }
                            if let meta = machine.metadata, !meta.isEmpty {
                                ForEach(meta.keys.sorted(), id: \.self) { k in
                                    HStack {
                                        Text(k)
                                            .font(.caption.monospaced().bold())
                                            .foregroundStyle(LiquidPalette.textPrimary)
                                        Text("=").foregroundStyle(LiquidPalette.textMuted)
                                        Text(meta[k] ?? "")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(LiquidPalette.textPrimary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .glassWell(cornerRadius: 8)
                                }
                            }
                            if let envs = machine.envNames, !envs.isEmpty {
                                Text("已配置环境变量名：\(envs.joined(separator: ", "))")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(LiquidPalette.textSecondary)
                            }
                        }
                        .padding(18)
                        .glassCard(cornerRadius: 18)
                    }
                }
                .padding([.horizontal, .bottom], 14)
                .padding(.top, 4)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
    }

    private var tabContentTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 18 * tabSlideDirection)),
            removal: .opacity.combined(with: .offset(x: -12 * tabSlideDirection))
        )
    }

    private func kvCell(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k)
                .font(.caption.weight(.medium))
                .foregroundStyle(LiquidPalette.textMuted)
            Text(v)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LiquidPalette.textPrimary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidWellInteractive(cornerRadius: 11)
    }

    private func alertCard(title: String, body: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            GlassIconOrb(systemImage: icon, tint: color, size: 32, iconSize: 15, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(color)
                Text(body)
                    .font(.caption)
                    .foregroundStyle(LiquidPalette.textPrimary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(14)
        .glassCard(cornerRadius: 16, tint: color.opacity(0.10))
    }

    private func patchMachine(_ req: UpdateMachineRequest) {
        guard let client = store.client else { return }
        isUpdatingConfig = true
        Task {
            defer { isUpdatingConfig = false }
            do {
                let outcome = try await client.updateMachine(id: machine.id, request: req)
                switch outcome {
                case .updated:
                    store.showToast(.success, "沙盒配置已更新")
                    await store.refreshMachinesAndUsageSilently()
                case .operation(let op):
                    store.showToast(.info, "正在应用沙盒配置变更…")
                    store.trackOperation(op, successMessage: "沙盒配置变更已完成")
                }
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }

    private func restoreFromSnapshot() {
        guard let client = store.client, !selectedRestoreSnapshotId.isEmpty else { return }
        Task {
            do {
                let op = try await client.restoreMachine(
                    id: machine.id,
                    request: RestoreMachineRequest(snapshotId: selectedRestoreSnapshotId, desiredState: "running")
                )
                store.showToast(.info, "正在从快照原地还原沙盒…")
                store.trackOperation(op, successMessage: "沙盒已成功还原至快照！")
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }

    private var saveSnapshotModal: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 9) {
                    GlassIconOrb(systemImage: "camera.aperture", tint: LiquidPalette.statusPurple, size: 30, iconSize: 14, cornerRadius: 9)
                    Text("保存沙盒快照")
                        .font(.headline)
                        .foregroundStyle(LiquidPalette.textPrimary)
                }

                TextField("快照名称（必填，如 clean-env-v1）", text: $snapshotName)
                    .textFieldStyle(.plain)
                    .foregroundStyle(LiquidPalette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .glassWell(cornerRadius: 10)

                TextField("备注描述（可选）", text: $snapshotDesc)
                    .textFieldStyle(.plain)
                    .foregroundStyle(LiquidPalette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .glassWell(cornerRadius: 10)

                HStack {
                    Spacer()
                    Button("取消") {
                        showSaveSnapshotSheet = false
                    }
                    .buttonStyle(.glass)

                    Button("保存快照") {
                        guard let client = store.client else { return }
                        isSavingSnapshot = true
                        Task {
                            defer { isSavingSnapshot = false }
                            do {
                                let snap = try await client.createSnapshot(
                                    machineId: machine.id,
                                    request: CreateSnapshotRequest(
                                        name: snapshotName.trimmingCharacters(in: .whitespacesAndNewlines),
                                        description: snapshotDesc.isEmpty ? nil : snapshotDesc
                                    )
                                )
                                store.showToast(.success, "快照 \(snap.name) 已创建（状态：\(snap.status)）")
                                showSaveSnapshotSheet = false
                                await store.refreshAll(silent: true)
                            } catch {
                                store.showToast(.error, error.localizedDescription)
                            }
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(snapshotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingSnapshot)
                }
            }
            .padding(22)
            .glassCard(cornerRadius: 22)
            .padding(14)
        }
        .frame(width: 440)
        .background { GlassBackdrop() }
    }
}
