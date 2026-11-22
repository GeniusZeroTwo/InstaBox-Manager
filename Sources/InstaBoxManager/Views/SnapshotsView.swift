import SwiftUI

struct SnapshotsView: View {
    @Environment(AppStore.self) private var store
    @ViewState private var inspectingSnapshot: SnapshotItem?
    @ViewState private var snapshotPendingDelete: SnapshotItem?
    @ViewState private var creatingFromSnapshot: SnapshotItem?
    @ViewState private var newSandboxName = ""

    var body: some View {
        VStack(spacing: 12) {
            GlassEffectContainer {
                HStack(spacing: 14) {
                    GlassIconOrb(
                        systemImage: "externaldrive.fill.badge.timemachine",
                        tint: .purple,
                        size: 40,
                        iconSize: 18,
                        cornerRadius: 13
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("快照镜像")
                            .font(.title3.weight(.semibold))
                        Text("浏览快照文件系统，或基于任意快照秒级克隆启动新沙盒。")
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
                .glassCard(cornerRadius: 20, tint: .purple.opacity(0.05))
            }
            .padding([.horizontal, .top], 14)

            if store.snapshots.isEmpty {
                ContentUnavailableView(
                    "暂无快照",
                    systemImage: "externaldrive.badge.timemachine",
                    description: Text("前往「沙盒实例」选择一台沙盒并保存快照后，将显示在此处。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCard(cornerRadius: 20)
                .padding([.horizontal, .bottom], 14)
            } else {
                ScrollView {
                    GlassEffectContainer(spacing: 12) {
                        LazyVStack(spacing: 10) {
                            ForEach(store.snapshots) { snap in
                                HStack(spacing: 14) {
                                    GlassIconOrb(
                                        systemImage: "externaldrive.fill.badge.timemachine",
                                        tint: .purple,
                                        size: 38,
                                        iconSize: 16,
                                        cornerRadius: 12
                                    )

                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(spacing: 8) {
                                            Text(snap.name)
                                                .font(.body.weight(.semibold))
                                            statusPill(snap.status)
                                            if snap.sizeLocked == true {
                                                Text("规格锁定")
                                                    .font(.caption2.weight(.medium))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .foregroundStyle(.secondary)
                                                    .glassPill()
                                            }
                                        }

                                        HStack(spacing: 10) {
                                            Text(snap.id)
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.secondary)
                                            Text("· 模板 \(snap.template.id)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            if let excl = snap.exclusiveBytes {
                                                Text("· 占用 \(Formatters.bytes(excl))")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Text("· \(Formatters.relativeOrShortTime(snap.createdAt))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        if let desc = snap.description, !desc.isEmpty {
                                            Text(desc)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    if snap.status == "ready" {
                                        Button {
                                            inspectingSnapshot = snap
                                        } label: {
                                            Label("浏览文件", systemImage: "folder")
                                        }
                                        .buttonStyle(.glass)
                                        .controlSize(.small)

                                        Button {
                                            newSandboxName = "\(snap.name)-box"
                                            creatingFromSnapshot = snap
                                        } label: {
                                            Label("创建沙盒", systemImage: "plus.circle")
                                        }
                                        .buttonStyle(.glassProminent)
                                        .controlSize(.small)
                                    }

                                    Button(role: .destructive) {
                                        snapshotPendingDelete = snap
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)
                                    .help("删除快照")
                                    .accessibilityLabel("删除快照 \(snap.name)")
                                }
                                .padding(16)
                                .glassCard(cornerRadius: 18, interactive: true)
                                .liquidHoverLift(scale: 1.008, liftY: -1.5, glowColor: .purple)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                        .animation(LiquidMotion.fluid, value: store.snapshots.map(\.id))
                    }
                }
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            }
        }
        .navigationTitle("快照镜像")
        .sheet(item: $inspectingSnapshot) { snap in
            SnapshotFileInspectorSheet(snapshot: snap)
                .environment(store)
        }
        .sheet(item: $creatingFromSnapshot) { snap in
            GlassEffectContainer {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        GlassIconOrb(systemImage: "plus.square.on.square", tint: .purple, size: 30, iconSize: 14, cornerRadius: 9)
                        Text("从快照「\(snap.name)」创建沙盒")
                            .font(.headline)
                    }
                    TextField("新沙盒名称", text: $newSandboxName)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .glassWell(cornerRadius: 10)
                    HStack {
                        Spacer()
                        Button("取消") { creatingFromSnapshot = nil }
                            .buttonStyle(.glass)
                        Button("立即创建并启动") {
                            createBox(from: snap)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
                .padding(20)
                .glassCard(cornerRadius: 22)
                .padding(12)
            }
            .frame(width: 420)
            .background { GlassBackdrop() }
        }
        .confirmationDialog(
            "确认删除快照？",
            isPresented: Binding(
                get: { snapshotPendingDelete != nil },
                set: { if !$0 { snapshotPendingDelete = nil } }
            ),
            presenting: snapshotPendingDelete
        ) { snap in
            Button("删除快照「\(snap.name)」", role: .destructive) {
                deleteSnapshot(snap)
                snapshotPendingDelete = nil
            }
            Button("取消", role: .cancel) {
                snapshotPendingDelete = nil
            }
        }
    }

    private func statusPill(_ status: String) -> some View {
        let color: Color = status == "ready" ? .green : (status == "pending" ? .orange : .red)
        return Text(status)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .glassPill(tint: color.opacity(0.20))
    }

    private func createBox(from snap: SnapshotItem) {
        guard let client = store.client else { return }
        let nameClean = newSandboxName.trimmingCharacters(in: .whitespacesAndNewlines)
        creatingFromSnapshot = nil
        Task {
            do {
                let op = try await client.createMachine(
                    CreateMachineRequest(
                        name: nameClean.isEmpty ? nil : nameClean,
                        snapshotId: snap.id,
                        desiredState: "running"
                    )
                )
                store.selectedMachineID = op.machineId
                store.selectedSection = .machines
                store.showToast(.info, "正在从快照 \(snap.name) 启动新沙盒…")
                store.trackOperation(op, successMessage: "基于快照的新沙盒已就绪！")
                await store.refreshMachinesAndUsageSilently()
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }

    private func deleteSnapshot(_ snap: SnapshotItem) {
        guard let client = store.client else { return }
        Task {
            do {
                try await client.deleteSnapshot(id: snap.id, confirmValue: snap.id)
                store.showToast(.info, "快照 \(snap.name) 已删除")
                await store.refreshAll(silent: true)
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }
}

private struct SnapshotFileInspectorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let snapshot: SnapshotItem

    @ViewState private var path: String = "/"
    @ViewState private var entries: [FileEntry] = []
    @ViewState private var previewContent: String?
    @ViewState private var isLoading = false

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                HStack {
                    HStack(spacing: 8) {
                        GlassIconOrb(systemImage: "folder", tint: .purple, size: 28, iconSize: 13, cornerRadius: 8)
                        Text("快照文件浏览：\(snapshot.name)")
                            .font(.headline)
                    }
                    Spacer()
                    Button("关闭") { dismiss() }
                        .buttonStyle(.glass)
                }

                HStack(spacing: 8) {
                    Button {
                        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
                        loadPath(parent.isEmpty ? "/" : parent)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.glass)
                    .disabled(path == "/")

                    TextField("/", text: $path)
                        .textFieldStyle(.plain)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassWell(cornerRadius: 9)
                        .onSubmit { loadPath(path) }

                    Button("读取") { loadPath(path) }
                        .buttonStyle(.glassProminent)
                }

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let previewContent {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("← 返回目录列表") {
                            self.previewContent = nil
                            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
                            loadPath(parent.isEmpty ? "/" : parent)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)

                        ScrollView {
                            Text(previewContent)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .glassCodeCanvas(cornerRadius: 12)
                    }
                } else {
                    List(entries) { entry in
                        HStack {
                            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text")
                                .foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
                            Text(entry.name)
                                .font(.caption.monospaced())
                            Spacer()
                            Text(entry.isDirectory ? "目录" : Formatters.bytes(entry.size))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            let next = path == "/" ? "/\(entry.name)" : "\(path)/\(entry.name)"
                            loadPath(next)
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .glassWell(cornerRadius: 12)
                }
            }
            .padding(18)
            .glassCard(cornerRadius: 22)
            .padding(12)
        }
        .frame(width: 640, height: 500)
        .background { GlassBackdrop() }
        .onAppear {
            loadPath("/")
        }
    }

    private func loadPath(_ target: String) {
        guard let client = store.client else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let res = try await client.fetchSnapshotFiles(snapshotId: snapshot.id, path: target)
                path = res.path
                if res.type == "dir" {
                    previewContent = nil
                    entries = res.entries ?? []
                } else {
                    previewContent = res.content ?? "(二进制或空文件)"
                }
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }
}
