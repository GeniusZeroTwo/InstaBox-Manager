import SwiftUI

enum MachineFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case running = "运行中"
    case suspended = "已暂停"
    case stopped = "已停止"

    var id: String { rawValue }
}

struct MachinesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var searchText = ""
    @ViewState private var filter: MachineFilter = .all
    @ViewState private var machinePendingDelete: MachineItem?

    private var filterSegments: [LiquidGlassSegmentItem<MachineFilter>] {
        MachineFilter.allCases.map { LiquidGlassSegmentItem(value: $0, title: $0.rawValue) }
    }

    private var filteredMachines: [MachineItem] {
        store.machines.filter { m in
            let matchesState: Bool
            switch filter {
            case .all: matchesState = true
            case .running: matchesState = m.state == .running || m.state == .starting || m.state == .resuming
            case .suspended: matchesState = m.state == .suspended || m.state == .suspending
            case .stopped: matchesState = m.state == .stopped || m.state == .stopping
            }
            guard matchesState else { return false }
            if searchText.trimmingCharacters(in: .whitespaces).isEmpty { return true }
            let q = searchText.lowercased()
            return m.name.lowercased().contains(q)
                || m.id.lowercased().contains(q)
                || m.template.id.lowercased().contains(q)
        }
    }

    var body: some View {
        @Bindable var bindableStore = store

        LiquidSplitView(
            storageKey: "instabox.machines.listWidth",
            pinnedSide: .leading,
            defaultWidth: 316,
            minPinnedWidth: 270,
            maxPinnedWidth: 420,
            minFlexibleWidth: 480
        ) {
            // Left column: Floating Liquid Glass Filter Deck & Sandbox List
            VStack(spacing: 10) {
                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(LiquidPalette.textSecondary)
                            TextField("搜索名称、ID 或模板…", text: $searchText)
                                .textFieldStyle(.plain)
                                .foregroundStyle(LiquidPalette.textPrimary)
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(LiquidPalette.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .help("清除搜索")
                                .accessibilityLabel("清除搜索")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .glassCard(cornerRadius: 14, interactive: true, elevated: false)

                        LiquidGlassSegmentedPicker(
                            items: filterSegments,
                            selection: $filter,
                            expandEqually: true,
                            compact: true
                        )
                    }
                }
                .padding([.leading, .top], 10)
                .padding(.trailing, 4)

                if filteredMachines.isEmpty {
                    ContentUnavailableView {
                        Label(store.machines.isEmpty ? "暂无沙盒实例" : "无匹配沙盒", systemImage: "cube.transparent")
                    } description: {
                        Text(store.machines.isEmpty ? "点击右上角「+」即可秒级创建一台 Linux / Android 云端沙盒。" : "尝试更换搜索关键词或筛选条件。")
                    } actions: {
                        if store.machines.isEmpty {
                            Button("新建沙盒") {
                                store.showCreateMachineSheet = true
                            }
                            .buttonStyle(.glassProminent)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassCard(cornerRadius: 18, elevated: false)
                    .padding([.leading, .bottom], 10)
                    .padding(.trailing, 4)
                } else {
                    List(selection: $bindableStore.selectedMachineID) {
                        ForEach(filteredMachines) { machine in
                            MachineRowView(machine: machine, operation: store.activeOperations[machine.id])
                                .tag(machine.id)
                                .listRowSeparator(.hidden)
                                .contextMenu {
                                    machineContextMenu(for: machine)
                                }
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .scrollEdgeEffectStyle(.soft, for: .vertical)
                    .animation(reduceMotion ? nil : LiquidMotion.snappy, value: filteredMachines.map(\.id))
                    .glassCard(cornerRadius: 18)
                    .padding([.leading, .bottom], 10)
                    .padding(.trailing, 4)
                }
            }
        } trailing: {
            // Right column: Selected Sandbox Inspector (strictly decoupled from split width)
            ZStack {
                if let machine = store.selectedMachine {
                    MachineDetailView(machine: machine)
                        .id(machine.id)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 6)),
                                    removal: .opacity
                                )
                        )
                } else {
                    ContentUnavailableView(
                        "请选择一台沙盒",
                        systemImage: "server.rack",
                        description: Text("从左侧列表选择沙盒以管理终端、文件、SSH、端口、远程桌面与监控。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : LiquidMotion.snappy, value: store.selectedMachineID)
        }
        .navigationTitle("沙盒实例")
        .confirmationDialog(
            "确认永久删除沙盒？",
            isPresented: Binding(
                get: { machinePendingDelete != nil },
                set: { if !$0 { machinePendingDelete = nil } }
            ),
            presenting: machinePendingDelete
        ) { machine in
            Button("永久删除「\(machine.name)」", role: .destructive) {
                Task { await store.deleteMachine(machine) }
                machinePendingDelete = nil
            }
            Button("取消", role: .cancel) {
                machinePendingDelete = nil
            }
        } message: { machine in
            Text("删除后沙盒 \(machine.name)（\(machine.id)）及其 /data 持久化磁盘数据将不可恢复。")
        }
    }

    @ViewBuilder
    private func machineContextMenu(for machine: MachineItem) -> some View {
        if machine.state == .stopped {
            Button {
                Task { await store.startMachine(machine) }
            } label: {
                Label("启动沙盒", systemImage: "play.fill")
            }
        }
        if machine.state == .suspended {
            Button {
                Task { await store.resumeMachine(machine) }
            } label: {
                Label("恢复运行 (Resume)", systemImage: "play.circle")
            }
        }
        if machine.state == .running {
            Button {
                Task { await store.openQuickSSH(for: machine) }
            } label: {
                Label("一键打开 SSH 终端", systemImage: "terminal")
            }
            Button {
                Task { await store.suspendMachine(machine) }
            } label: {
                Label("暂停沙盒 (保留内存)", systemImage: "pause.fill")
            }
            Button {
                Task { await store.stopMachine(machine) }
            } label: {
                Label("关机停止 (Stop)", systemImage: "stop.fill")
            }
        }
        Button {
            Task { await store.restartMachine(machine) }
        } label: {
            Label("重启沙盒", systemImage: "arrow.clockwise")
        }
        Button {
            Task { await store.forkMachine(machine, newName: "\(machine.name)-fork") }
        } label: {
            Label("快速克隆 (Fork)", systemImage: "doc.on.doc")
        }
        Divider()
        Button("复制沙盒 ID") {
            TerminalLauncher.copyToClipboard(machine.id)
        }
        Button(role: .destructive) {
            machinePendingDelete = machine
        } label: {
            Label("删除沙盒…", systemImage: "trash")
        }
    }
}

private struct MachineRowView: View {
    let machine: MachineItem
    let operation: OperationItem?

    @ViewState private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.backgroundProminence) private var backgroundProminence

    private var orbTint: Color {
        if operation != nil || machine.state.isTransitioning { return LiquidPalette.statusOrange }
        switch machine.state {
        case .running: return LiquidPalette.statusGreen
        case .suspended: return LiquidPalette.statusIndigo
        case .error: return LiquidPalette.statusRed
        default: return LiquidPalette.statusBlue
        }
    }

    var body: some View {
        let primaryText = LiquidPalette.rowPrimary(prominence: backgroundProminence)
        let secondaryText = LiquidPalette.rowSecondary(prominence: backgroundProminence)
        let mutedText = LiquidPalette.rowMuted(prominence: backgroundProminence)

        HStack(alignment: .top, spacing: 11) {
            GlassIconOrb(
                systemImage: "cube.transparent.fill",
                tint: orbTint,
                size: 36,
                iconSize: 15,
                cornerRadius: 11
            )
            .shadow(color: isHovered ? orbTint.opacity(0.32) : .clear, radius: 8)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    Text(machine.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                        .help(machine.name)
                    Spacer(minLength: 0)
                    StateBadge(state: machine.state, operation: operation)
                        .fixedSize()
                }

                HStack(spacing: 6) {
                    Text(machine.template.id)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text("· \(machine.spec.displayLabel)")
                        .font(.caption)
                        .lineLimit(1)
                    if let storage = machine.storage {
                        Text("· \(storage.sizeGiB) GiB")
                            .font(.caption.monospacedDigit())
                            .fixedSize()
                    }
                }
                .foregroundStyle(secondaryText)

                HStack {
                    Text(machine.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(mutedText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(machine.id)
                    Spacer(minLength: 4)
                    if let oom = machine.oomKills, oom > 0 {
                        Label("OOM:\(oom)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(LiquidPalette.statusOrange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .glassPill(tint: LiquidPalette.statusOrange)
                            .fixedSize()
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : LiquidMotion.snappy) {
                isHovered = hovering
            }
        }
    }
}
