import AppKit
import SwiftUI

struct FileBrowserTab: View {
    @Environment(AppStore.self) private var store
    let machine: MachineItem

    @ViewState private var currentPath: String = "/data/home"
    @ViewState private var entries: [FileEntry] = []
    @ViewState private var isLoading = false
    @ViewState private var errorMessage: String?

    // File Editor Modal
    @ViewState private var editingFilePath: String?
    @ViewState private var editingContent: String = ""
    @ViewState private var isSavingFile = false

    // New Folder / New File
    @ViewState private var showNewFolderSheet = false
    @ViewState private var newItemName = ""
    @ViewState private var newItemIsFile = false

    private let shortcuts = ["/data/home", "/data", "/tmp", "/etc", "/"]

    var body: some View {
        VStack(spacing: 10) {
            // Floating Liquid Glass Path & Actions Toolbar
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        navigateUp()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.glass)
                    .disabled(currentPath == "/")
                    .help("返回上级目录")

                    TextField("/data/home", text: $currentPath)
                        .textFieldStyle(.plain)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(LiquidPalette.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassWell(cornerRadius: 9)
                        .frame(minWidth: 140)
                        .onSubmit {
                            loadDirectory(currentPath)
                        }

                    Menu("常用目录") {
                        ForEach(shortcuts, id: \.self) { p in
                            Button(p) {
                                loadDirectory(p)
                            }
                        }
                    }
                    .buttonStyle(.glass)
                    .fixedSize()

                    Button {
                        loadDirectory(currentPath)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, isActive: isLoading)
                    }
                    .buttonStyle(.glass)
                    .help("刷新当前目录")

                    Button {
                        newItemIsFile = false
                        newItemName = ""
                        showNewFolderSheet = true
                    } label: {
                        Label("新建目录", systemImage: "folder.badge.plus")
                            .lineLimit(1)
                    }
                    .buttonStyle(.glass)
                    .fixedSize()

                    Button {
                        newItemIsFile = true
                        newItemName = "untitled.txt"
                        showNewFolderSheet = true
                    } label: {
                        Label("新建文件", systemImage: "doc.badge.plus")
                            .lineLimit(1)
                    }
                    .buttonStyle(.glass)
                    .fixedSize()

                    Button {
                        uploadFileWithOpenPanel()
                    } label: {
                        Label("上传", systemImage: "square.and.arrow.up")
                            .lineLimit(1)
                    }
                    .buttonStyle(.glassProminent)
                    .fixedSize()
                }
                .padding(12)
                .glassCard(cornerRadius: 16, elevated: false)
            }
            .padding(.horizontal, 12)

            Group {
                if machine.state != .running {
                    ContentUnavailableView("沙盒未运行", systemImage: "bolt.slash", description: Text("请先启动或恢复沙盒以浏览、编辑和上传下载文件。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .glassCard(cornerRadius: 18)
                } else if isLoading && entries.isEmpty {
                    ProgressView("正在读取目录 \(currentPath)…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .glassCard(cornerRadius: 18)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("无法读取路径", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("返回 /data/home") {
                            loadDirectory("/data/home")
                        }
                        .buttonStyle(.glassProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassCard(cornerRadius: 18)
                } else if entries.isEmpty {
                    ContentUnavailableView("空目录", systemImage: "folder", description: Text("当前目录没有任何文件，可点击上方「上传文件」或「新建文件」。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .glassCard(cornerRadius: 18)
                } else {
                    List {
                        ForEach(sortedEntries) { entry in
                            HStack(spacing: 10) {
                                Image(systemName: iconForEntry(entry))
                                    .foregroundStyle(entry.isDirectory ? LiquidPalette.statusBlue : LiquidPalette.textSecondary)
                                    .frame(width: 20)

                                Text(entry.name)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .fontWeight(entry.isDirectory ? .semibold : .regular)
                                    .foregroundStyle(LiquidPalette.textPrimary)
                                    .lineLimit(1)

                                if let target = entry.target {
                                    Text("→ \(target)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(LiquidPalette.textSecondary)
                                }

                                Spacer()

                                Text(entry.mode)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(LiquidPalette.textMuted)

                                Text(entry.isDirectory ? "目录" : Formatters.bytes(entry.size))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(LiquidPalette.textSecondary)
                                    .frame(width: 85, alignment: .trailing)

                                Text(Formatters.relativeOrShortTime(entry.modTime))
                                    .font(.caption2)
                                    .foregroundStyle(LiquidPalette.textMuted)
                                    .frame(width: 80, alignment: .trailing)

                                HStack(spacing: 6) {
                                    if !entry.isDirectory {
                                        Button {
                                            openTextEditor(for: entry)
                                        } label: {
                                            Image(systemName: "pencil.and.outline")
                                        }
                                        .buttonStyle(.borderless)
                                        .help("在线查看 / 编辑文本")

                                        Button {
                                            downloadEntry(entry)
                                        } label: {
                                            Image(systemName: "arrow.down.circle")
                                        }
                                        .buttonStyle(.borderless)
                                        .help("下载到本地 Mac")
                                    }

                                    Button(role: .destructive) {
                                        deleteEntry(entry)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("删除")
                                }
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                if entry.isDirectory {
                                    loadDirectory(joinPath(currentPath, entry.name))
                                } else {
                                    openTextEditor(for: entry)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .scrollEdgeEffectStyle(.soft, for: .vertical)
                    .glassCard(cornerRadius: 18)
                }
            }
            .padding([.horizontal, .bottom], 12)
        }
        .onAppear {
            if machine.state == .running {
                loadDirectory(currentPath)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingFilePath != nil },
            set: { if !$0 { editingFilePath = nil } }
        )) {
            fileEditorModal
        }
        .sheet(isPresented: $showNewFolderSheet) {
            newItemModal
        }
    }

    private var sortedEntries: [FileEntry] {
        entries.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private func iconForEntry(_ e: FileEntry) -> String {
        switch e.type {
        case "dir": return "folder.fill"
        case "symlink": return "link"
        default: return "doc.text"
        }
    }

    private func joinPath(_ base: String, _ child: String) -> String {
        if base == "/" { return "/\(child)" }
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        return "\(trimmed)/\(child)"
    }

    private func navigateUp() {
        let url = URL(fileURLWithPath: currentPath).deletingLastPathComponent()
        loadDirectory(url.path.isEmpty ? "/" : url.path)
    }

    private func loadDirectory(_ path: String) {
        guard let client = store.client, machine.state == .running else { return }
        isLoading = true
        errorMessage = nil
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "/" : path

        Task {
            defer { isLoading = false }
            do {
                let res = try await client.fetchFiles(machineId: machine.id, path: normalized)
                if res.type == "dir" {
                    currentPath = res.path
                    entries = res.entries ?? []
                } else {
                    editingFilePath = res.path
                    editingContent = res.content ?? ""
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openTextEditor(for entry: FileEntry) {
        guard let client = store.client else { return }
        let fullPath = joinPath(currentPath, entry.name)
        Task {
            do {
                let res = try await client.fetchFiles(machineId: machine.id, path: fullPath)
                if res.binary == true {
                    store.showToast(.info, "该文件为二进制文件，请使用右侧下载按钮保存到本地查看。")
                    return
                }
                editingFilePath = fullPath
                editingContent = res.content ?? ""
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }

    private func uploadFileWithOpenPanel() {
        guard let client = store.client else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "上传到沙盒"

        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task {
            for fileURL in urls {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let remoteTarget = joinPath(currentPath, fileURL.lastPathComponent)
                    _ = try await client.uploadFile(machineId: machine.id, remotePath: remoteTarget, data: data)
                    store.showToast(.success, "已上传 \(fileURL.lastPathComponent)")
                } catch {
                    store.showToast(.error, "上传 \(fileURL.lastPathComponent) 失败：\(error.localizedDescription)")
                }
            }
            loadDirectory(currentPath)
        }
    }

    private func downloadEntry(_ entry: FileEntry) {
        guard let client = store.client else { return }
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = entry.name
        savePanel.prompt = "下载保存"
        guard savePanel.runModal() == .OK, let destURL = savePanel.url else { return }

        let remotePath = joinPath(currentPath, entry.name)
        Task {
            do {
                let data = try await client.downloadFileContent(machineId: machine.id, remotePath: remotePath)
                try data.write(to: destURL)
                store.showToast(.success, "已保存至 \(destURL.lastPathComponent)")
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }

    private func deleteEntry(_ entry: FileEntry) {
        guard let client = store.client else { return }
        let target = joinPath(currentPath, entry.name)
        Task {
            do {
                let res = try await client.execCommand(
                    machineId: machine.id,
                    request: ExecRequest(argv: ["rm", "-rf", "--", target], noHistory: true)
                )
                if res.exitCode == 0 {
                    store.showToast(.info, "已删除 \(entry.name)")
                    loadDirectory(currentPath)
                } else {
                    store.showToast(.error, res.stderr.isEmpty ? "删除失败 (Exit \(res.exitCode))" : res.stderr)
                }
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }

    private var fileEditorModal: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 8) {
                        GlassIconOrb(systemImage: "doc.text", tint: LiquidPalette.statusBlue, size: 28, iconSize: 13, cornerRadius: 8)
                        Text(editingFilePath ?? "")
                            .font(.subheadline.monospaced().bold())
                            .foregroundStyle(LiquidPalette.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("取消") {
                        editingFilePath = nil
                    }
                    .buttonStyle(.glass)

                    Button("保存到沙盒") {
                        guard let client = store.client, let path = editingFilePath else { return }
                        isSavingFile = true
                        Task {
                            defer { isSavingFile = false }
                            do {
                                _ = try await client.uploadFile(
                                    machineId: machine.id,
                                    remotePath: path,
                                    data: Data(editingContent.utf8)
                                )
                                store.showToast(.success, "已保存 \(path)")
                                editingFilePath = nil
                                loadDirectory(currentPath)
                            } catch {
                                store.showToast(.error, error.localizedDescription)
                            }
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isSavingFile)
                }

                TextEditor(text: $editingContent)
                    .font(.system(size: 12.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .glassCodeCanvas(cornerRadius: 12)
            }
            .padding(18)
            .glassCard(cornerRadius: 22)
            .padding(12)
        }
        .frame(width: 700, height: 520)
        .background { GlassBackdrop() }
    }

    private var newItemModal: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    GlassIconOrb(
                        systemImage: newItemIsFile ? "doc.badge.plus" : "folder.badge.plus",
                        tint: LiquidPalette.statusBlue,
                        size: 28,
                        iconSize: 13,
                        cornerRadius: 8
                    )
                    Text(newItemIsFile ? "新建空文件" : "新建文件夹")
                        .font(.headline)
                        .foregroundStyle(LiquidPalette.textPrimary)
                }

                TextField("名称", text: $newItemName)
                    .textFieldStyle(.plain)
                    .foregroundStyle(LiquidPalette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .glassWell(cornerRadius: 10)

                HStack {
                    Spacer()
                    Button("取消") {
                        showNewFolderSheet = false
                    }
                    .buttonStyle(.glass)

                    Button("创建") {
                        guard let client = store.client else { return }
                        let clean = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !clean.isEmpty else { return }
                        let full = joinPath(currentPath, clean)
                        Task {
                            do {
                                if newItemIsFile {
                                    showNewFolderSheet = false
                                    editingFilePath = full
                                    editingContent = ""
                                } else {
                                    _ = try await client.execCommand(
                                        machineId: machine.id,
                                        request: ExecRequest(argv: ["mkdir", "-p", "--", full], noHistory: true)
                                    )
                                    showNewFolderSheet = false
                                    loadDirectory(currentPath)
                                }
                            } catch {
                                store.showToast(.error, error.localizedDescription)
                            }
                        }
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .padding(20)
            .glassCard(cornerRadius: 22)
            .padding(12)
        }
        .frame(width: 380)
        .background { GlassBackdrop() }
    }
}
