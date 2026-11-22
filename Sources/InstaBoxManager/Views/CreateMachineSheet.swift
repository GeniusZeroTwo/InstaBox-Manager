import SwiftUI

struct CreateMachineSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum SourceMode: String, CaseIterable, Identifiable, Sendable {
        case template = "官方模板"
        case snapshot = "已有快照"
        var id: String { rawValue }
    }

    @ViewState private var sourceMode: SourceMode = .template
    @ViewState private var name: String = ""
    @ViewState private var selectedTemplateId: String = "agent-browser"
    @ViewState private var selectedSnapshotId: String = ""
    @ViewState private var selectedSpecIndex: Int = 0
    @ViewState private var startImmediately: Bool = true
    @ViewState private var idleMinutesChoice: Int = 30 // 0 = off, 5..30
    @ViewState private var envText: String = ""
    @ViewState private var metadataText: String = ""
    @ViewState private var isSubmitting = false
    @ViewState private var errorMessage: String?

    private var sourceModeSegments: [LiquidGlassSegmentItem<SourceMode>] {
        [
            LiquidGlassSegmentItem(value: .template, title: "官方模板", icon: "cube.box"),
            LiquidGlassSegmentItem(value: .snapshot, title: "已有快照", icon: "externaldrive.badge.timemachine")
        ]
    }

    private var creatableTemplates: [TemplateItem] {
        let visible = store.templates.filter { $0.hidden != true && $0.creatable != false }
        if !visible.isEmpty { return visible }
        return [
            TemplateItem(
                id: "agent-browser",
                version: "latest",
                arch: "amd64",
                digest: "",
                description: "Debian 13 + Docker, Node.js, Python, Go, Rust, Desktop & Chromium",
                creatable: true,
                default: true,
                hidden: false,
                restricted: false,
                gpu: false,
                os: nil,
                defaultSpec: MachineSpec(vcpus: 4, memMiB: 8192, persistentDiskGiB: 20, rootDiskGiB: 16, gpuType: nil, gpus: nil),
                sizes: nil
            )
        ]
    }

    private var readySnapshots: [SnapshotItem] {
        store.snapshots.filter { $0.status == "ready" }
    }

    private var isFreeTier: Bool {
        let tier = (store.currentOrg?.tier ?? store.usage?.org?.tier ?? "free").lowercased()
        return tier == "free"
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                // Floating Glass Header
                HStack(spacing: 10) {
                    GlassIconOrb(systemImage: "plus.square.on.square", tint: .accentColor, size: 34, iconSize: 15, cornerRadius: 11)
                    Text("创建新 InstaBox 沙盒")
                        .font(.title3.bold())
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassCard(cornerRadius: 16, elevated: false)

                Form {
                    Section("基础信息") {
                        TextField("沙盒名称（可选，如 dev-box-1，留空自动生成）", text: $name)

                        HStack {
                            Text("创建来源")
                            Spacer()
                            LiquidGlassSegmentedPicker(
                                items: sourceModeSegments,
                                selection: $sourceMode
                            )
                        }

                        if sourceMode == .template {
                            Picker("系统模板", selection: $selectedTemplateId) {
                                ForEach(creatableTemplates) { tpl in
                                    Text("\(tpl.id)\(tpl.description.map { " — \($0)" } ?? "")")
                                        .tag(tpl.id)
                                }
                            }
                            if isFreeTier {
                                Text("提示：免费套餐支持 agent-browser、android、omarchy、ci 模板或从快照创建。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            if readySnapshots.isEmpty {
                                Text("当前工作区暂无可用（ready）快照，请先从沙盒保存快照或改用官方模板。")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                Picker("选择快照", selection: $selectedSnapshotId) {
                                    ForEach(readySnapshots) { snap in
                                        Text("\(snap.name) (\(snap.id))").tag(snap.id)
                                    }
                                }
                            }
                        }
                    }

                    Section("硬件规格与生命周期") {
                        let specs = store.allowedSpecs
                        Picker("计算规格 (vCPU / 内存)", selection: $selectedSpecIndex) {
                            ForEach(Array(specs.enumerated()), id: \.offset) { idx, spec in
                                Text(spec.displayLabel).tag(idx)
                            }
                        }
                        .disabled(specs.count <= 1)

                        Toggle("创建后立即启动运行", isOn: $startImmediately)

                        if !isFreeTier {
                            Picker("空闲自动暂停 (Auto-Pause)", selection: $idleMinutesChoice) {
                                Text("5 分钟").tag(5)
                                Text("10 分钟").tag(10)
                                Text("15 分钟").tag(15)
                                Text("30 分钟（默认）").tag(30)
                                if store.me?.alwaysOnAllowed == true || store.currentOrg?.limits?.alwaysOn == true {
                                    Text("永不自动暂停 (Always On)").tag(0)
                                }
                            }
                        } else {
                            LabeledContent("空闲自动暂停", value: "30 分钟（免费版固定）")
                                .font(.subheadline)
                        }
                    }

                    Section("环境变量与标签（可选，每行 KEY=VALUE）") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("环境变量 (env)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $envText)
                                .font(.system(.caption, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .padding(4)
                                .frame(height: 58)
                                .glassCodeCanvas(cornerRadius: 8)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("元数据标签 (metadata)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $metadataText)
                                .font(.system(.caption, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .padding(4)
                                .frame(height: 48)
                                .glassCodeCanvas(cornerRadius: 8)
                        }
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .scrollEdgeEffectStyle(.soft, for: .vertical)
                .glassCard(cornerRadius: 18)

                // Floating Glass Action Footer
                HStack {
                    Spacer()
                    Button("取消") {
                        dismiss()
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)

                    Button {
                        submitCreate()
                    } label: {
                        HStack(spacing: 6) {
                            if isSubmitting {
                                ProgressView().controlSize(.small)
                            }
                            Text(isSubmitting ? "正在提交…" : "立即创建")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isSubmitting || (sourceMode == .snapshot && readySnapshots.isEmpty))
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassCard(cornerRadius: 16, elevated: false)
            }
            .padding(12)
        }
        .frame(width: 580, height: 630)
        .background { GlassBackdrop() }
        .onAppear {
            if let defTpl = creatableTemplates.first(where: { $0.default == true }) ?? creatableTemplates.first {
                selectedTemplateId = defTpl.id
            }
            if let firstSnap = readySnapshots.first {
                selectedSnapshotId = firstSnap.id
            }
        }
    }

    private func parseKeyValueLines(_ raw: String) -> [String: String]? {
        var dict: [String: String] = [:]
        for line in raw.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
            let val = String(trimmed[trimmed.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                dict[key] = val
            }
        }
        return dict.isEmpty ? nil : dict
    }

    private func submitCreate() {
        guard let client = store.client else { return }
        isSubmitting = true
        errorMessage = nil

        let specs = store.allowedSpecs
        let chosenSpec = specs.indices.contains(selectedSpecIndex) ? specs[selectedSpecIndex] : nil
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        var req = CreateMachineRequest(
            name: cleanName.isEmpty ? nil : cleanName,
            templateId: sourceMode == .template ? selectedTemplateId : nil,
            snapshotId: sourceMode == .snapshot ? selectedSnapshotId : nil,
            vcpus: specs.count > 1 ? chosenSpec?.vcpus : nil,
            memMiB: specs.count > 1 ? chosenSpec?.memMiB : nil,
            desiredState: startImmediately ? "running" : "stopped",
            autoSuspendAfterSeconds: isFreeTier ? nil : (idleMinutesChoice == 0 ? 0 : idleMinutesChoice * 60),
            env: parseKeyValueLines(envText),
            metadata: parseKeyValueLines(metadataText)
        )

        // Avoid passing vcpus/memMiB when creating from a sizeLocked snapshot
        if sourceMode == .snapshot,
           let snap = readySnapshots.first(where: { $0.id == selectedSnapshotId }),
           snap.sizeLocked == true {
            req.vcpus = nil
            req.memMiB = nil
        }

        Task {
            do {
                let op = try await client.createMachine(req)
                store.selectedMachineID = op.machineId
                store.selectedSection = .machines
                store.showToast(.info, "已提交创建沙盒请求，正在分配节点…")
                store.trackOperation(op, successMessage: "新沙盒已就绪！")
                await store.refreshMachinesAndUsageSilently()
                isSubmitting = false
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
