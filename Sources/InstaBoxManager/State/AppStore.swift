import Foundation
import Observation
import SwiftUI

public enum SidebarSection: Hashable, Identifiable {
    case overview
    case machines
    case snapshots
    case ports
    case secretsAndWebhooks
    case mcpServer
    case addAccount

    public var id: Self { self }

    public var title: String {
        switch self {
        case .overview: return "概览与配额"
        case .machines: return "沙盒实例"
        case .snapshots: return "快照镜像"
        case .ports: return "公网端口"
        case .secretsAndWebhooks: return "密钥与 Webhook"
        case .mcpServer: return "MCP 服务"
        case .addAccount: return "切换 / 添加 API"
        }
    }

    public var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .machines: return "server.rack"
        case .snapshots: return "externaldrive.badge.timemachine"
        case .ports: return "network"
        case .secretsAndWebhooks: return "key.horizontal"
        case .mcpServer: return "point.3.connected.trianglepath.dotted"
        case .addAccount: return "person.badge.key"
        }
    }
}

public struct BannerToast: Identifiable, Equatable {
    public enum Kind {
        case success, info, error
    }
    public let id = UUID()
    public let kind: Kind
    public let message: String
}

@MainActor
@Observable
public final class AppStore {
    // Profiles & Auth
    public var profiles: [APIProfile] = []
    public var activeProfileID: UUID?
    public var isAuthenticating = false
    public var authError: String?

    // Navigation
    public var selectedSection: SidebarSection = .machines
    public var selectedMachineID: String?
    public var showCreateMachineSheet = false

    // Cached API Data
    public var me: MeResponse?
    public var orgs: [OrgItem] = []
    public var usage: UsageResponse?
    public var machineUsages: [OrgMachineUsageItem] = []
    public var templates: [TemplateItem] = []
    public var machines: [MachineItem] = []
    public var snapshots: [SnapshotItem] = []
    public var allPorts: [PublicPortItem] = []
    public var portsEnabled: Bool = true
    public var secrets: [OrgSecretItem] = []
    public var webhooks: [WebhookItem] = []
    public var webhookEventTypes: [String] = []

    // Loading & Operation States
    public var isRefreshing = false
    public var lastRefreshedAt: Date?
    public var activeOperations: [String: OperationItem] = [:] // machineId -> OperationItem
    public var toast: BannerToast?

    // Preferences
    public var autoRefreshSeconds: Int = 15 {
        didSet {
            UserDefaults.standard.set(autoRefreshSeconds, forKey: "instabox.autoRefreshSeconds")
            restartAutoRefreshTask()
        }
    }

    public var preferredTerminal: TerminalAppPreference = .terminal {
        didSet {
            UserDefaults.standard.set(preferredTerminal.rawValue, forKey: "instabox.preferredTerminal")
        }
    }

    // MCP Server State
    public var mcpServerRunning = false
    public var mcpServerError: String?
    public var mcpLogs: [MCPLogEntry] = []
    public var mcpServerPort: Int = 28765 {
        didSet {
            let clamped = min(max(mcpServerPort, 1024), 65535)
            if clamped != mcpServerPort {
                mcpServerPort = clamped
                return
            }
            UserDefaults.standard.set(mcpServerPort, forKey: "instabox.mcp.port")
        }
    }
    public var mcpAutoStart: Bool = false {
        didSet {
            UserDefaults.standard.set(mcpAutoStart, forKey: "instabox.mcp.autoStart")
        }
    }

    private var mcpEngine: MCPServerEngine?
    private var mcpHTTPServer: MCPHTTPServer?
    private var autoRefreshTask: Task<Void, Never>?

    public init() {
        let savedInterval = UserDefaults.standard.integer(forKey: "instabox.autoRefreshSeconds")
        if savedInterval > 0 {
            self.autoRefreshSeconds = savedInterval
        }
        if let termRaw = UserDefaults.standard.string(forKey: "instabox.preferredTerminal"),
           let pref = TerminalAppPreference(rawValue: termRaw) {
            self.preferredTerminal = pref
        }
        let savedPort = UserDefaults.standard.integer(forKey: "instabox.mcp.port")
        if (1024...65535).contains(savedPort) {
            self.mcpServerPort = savedPort
        }
        self.mcpAutoStart = UserDefaults.standard.bool(forKey: "instabox.mcp.autoStart")

        self.profiles = KeychainService.loadProfiles()
        if let savedActive = KeychainService.loadActiveProfileID(),
           profiles.contains(where: { $0.id == savedActive }),
           KeychainService.loadAPIKey(for: savedActive) != nil {
            self.activeProfileID = savedActive
            Task {
                await refreshAll(silent: true)
                restartAutoRefreshTask()
            }
        } else if let first = profiles.first, KeychainService.loadAPIKey(for: first.id) != nil {
            self.activeProfileID = first.id
            KeychainService.saveActiveProfileID(first.id)
            Task {
                await refreshAll(silent: true)
                restartAutoRefreshTask()
            }
        }

        setupMCPEngine()
        if mcpAutoStart {
            startMCPServer(silent: true)
        }
    }

    public var activeProfile: APIProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first(where: { $0.id == activeProfileID })
    }

    public var isConnected: Bool {
        guard let profile = activeProfile else { return false }
        return KeychainService.loadAPIKey(for: profile.id) != nil
    }

    public var client: InstaBoxClient? {
        guard let profile = activeProfile,
              let key = KeychainService.loadAPIKey(for: profile.id) else {
            return nil
        }
        return InstaBoxClient(baseURL: profile.normalizedBaseURL, apiKey: key)
    }

    public var currentOrg: OrgItem? {
        if let orgId = usage?.org?.id ?? me?.org?.id ?? me?.orgId {
            return orgs.first(where: { $0.id == orgId }) ?? orgs.first
        }
        return orgs.first
    }

    public var allowedSpecs: [MachineSpec] {
        if let specs = currentOrg?.allowedSpecs, !specs.isEmpty { return specs }
        if let specs = me?.allowedSpecs, !specs.isEmpty { return specs }
        if let specs = usage?.limits.machineSpecs, !specs.isEmpty { return specs }
        if let single = usage?.limits.machineSpec { return [single] }
        return [MachineSpec(vcpus: 4, memMiB: 8192, persistentDiskGiB: 20, rootDiskGiB: nil, gpuType: nil, gpus: nil)]
    }

    public var selectedMachine: MachineItem? {
        guard let selectedMachineID else { return nil }
        return machines.first(where: { $0.id == selectedMachineID })
    }

    public var runningMachineCount: Int {
        machines.filter { $0.state == .running }.count
    }

    // MARK: - Toast Notifications

    public func showToast(_ kind: BannerToast.Kind, _ message: String) {
        let newToast = BannerToast(kind: kind, message: message)
        self.toast = newToast
        Task {
            try? await Task.sleep(for: .seconds(kind == .error ? 5 : 3))
            if self.toast?.id == newToast.id {
                self.toast = nil
            }
        }
    }

    // MARK: - Authentication & Multi-Profile Management

    public func connectWithAPIKey(rawKey: String, customName: String = "", baseURL: String = "https://api.instabox.sh") async -> Bool {
        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            authError = "请输入 InstaBox API Key（以 ibk_ 开头）。"
            return false
        }

        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }

        let tempClient = InstaBoxClient(baseURL: baseURL, apiKey: trimmedKey)
        do {
            // Validate key against /v1/machines + optional /v1/me & /v1/orgs (in case key has narrow scopes)
            let fetchedMachines = try await tempClient.fetchMachines()
            let fetchedMe = try? await tempClient.fetchMe()
            let fetchedOrgs = (try? await tempClient.fetchOrgs()) ?? []
            let fetchedUsage = try? await tempClient.fetchUsage(orgId: fetchedOrgs.first?.id)

            let primaryOrg = fetchedOrgs.first
            let resolvedOrgName = primaryOrg?.name ?? fetchedMe?.org?.name ?? fetchedUsage?.org?.name
            let resolvedTier = primaryOrg?.tier ?? fetchedMe?.org?.tier ?? fetchedUsage?.org?.tier
            let resolvedLogin = fetchedMe?.login

            let displayLabel: String
            if !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                displayLabel = customName.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let orgName = resolvedOrgName, !orgName.isEmpty {
                displayLabel = orgName
            } else if let login = resolvedLogin, !login.isEmpty {
                displayLabel = login
            } else {
                displayLabel = "InstaBox (\(KeychainService.maskKey(trimmedKey)))"
            }

            let profile = APIProfile(
                name: displayLabel,
                baseURL: tempClient.baseURL,
                keyPrefix: KeychainService.maskKey(trimmedKey),
                userLogin: resolvedLogin,
                orgId: primaryOrg?.id ?? fetchedMe?.org?.id,
                orgName: resolvedOrgName,
                tier: resolvedTier
            )

            try KeychainService.saveAPIKey(trimmedKey, for: profile.id)
            profiles.append(profile)
            KeychainService.saveProfiles(profiles)

            activeProfileID = profile.id
            KeychainService.saveActiveProfileID(profile.id)

            self.machines = fetchedMachines
            self.me = fetchedMe
            self.orgs = fetchedOrgs
            self.usage = fetchedUsage
            self.selectedMachineID = fetchedMachines.first?.id
            self.selectedSection = .machines

            showToast(.success, "已连接工作区：\(displayLabel)")
            await refreshAll(silent: true)
            restartAutoRefreshTask()
            return true
        } catch {
            authError = error.localizedDescription
            return false
        }
    }

    public func switchProfile(_ profile: APIProfile) {
        guard profile.id != activeProfileID else { return }
        activeProfileID = profile.id
        KeychainService.saveActiveProfileID(profile.id)
        clearWorkspaceCache()
        selectedSection = .machines
        showToast(.info, "已切换至：\(profile.name)")
        Task {
            await refreshAll(silent: false)
            restartAutoRefreshTask()
        }
    }

    public func removeProfile(_ profile: APIProfile) {
        KeychainService.deleteAPIKey(for: profile.id)
        profiles.removeAll { $0.id == profile.id }
        KeychainService.saveProfiles(profiles)

        if activeProfileID == profile.id {
            activeProfileID = profiles.first?.id
            KeychainService.saveActiveProfileID(activeProfileID)
            clearWorkspaceCache()
            if activeProfileID != nil {
                Task { await refreshAll(silent: false) }
            } else {
                autoRefreshTask?.cancel()
            }
        }
    }

    private func clearWorkspaceCache() {
        me = nil
        orgs = []
        usage = nil
        machineUsages = []
        templates = []
        machines = []
        snapshots = []
        allPorts = []
        secrets = []
        webhooks = []
        selectedMachineID = nil
        activeOperations = [:]
    }

    // MARK: - Refresh Data

    public func restartAutoRefreshTask() {
        autoRefreshTask?.cancel()
        guard isConnected, autoRefreshSeconds > 0 else { return }
        let interval = autoRefreshSeconds
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self, self.isConnected else { break }
                await self.refreshMachinesAndUsageSilently()
            }
        }
    }

    public func refreshMachinesAndUsageSilently() async {
        guard let client else { return }
        if let updatedMachines = try? await client.fetchMachines() {
            self.machines = updatedMachines
            if selectedMachineID == nil || !updatedMachines.contains(where: { $0.id == selectedMachineID }) {
                selectedMachineID = updatedMachines.first?.id
            }
        }
        if let updatedUsage = try? await client.fetchUsage(orgId: currentOrg?.id) {
            self.usage = updatedUsage
        }
        self.lastRefreshedAt = Date()
    }

    public func refreshAll(silent: Bool = false) async {
        guard let client else { return }
        if !silent { isRefreshing = true }
        defer {
            isRefreshing = false
            lastRefreshedAt = Date()
        }

        async let meTask = try? client.fetchMe()
        async let orgsTask = try? client.fetchOrgs()
        async let templatesTask = try? client.fetchTemplates()
        async let machinesTask = client.fetchMachines()
        async let snapshotsTask = try? client.fetchSnapshots()
        async let portsTask = try? client.fetchAllPorts()

        do {
            let fetchedMachines = try await machinesTask
            self.machines = fetchedMachines
            if selectedMachineID == nil || !fetchedMachines.contains(where: { $0.id == selectedMachineID }) {
                selectedMachineID = fetchedMachines.first?.id
            }
        } catch {
            if !silent {
                showToast(.error, error.localizedDescription)
            }
        }

        if let m = await meTask { self.me = m }
        if let o = await orgsTask { self.orgs = o }
        if let t = await templatesTask { self.templates = t }
        if let s = await snapshotsTask { self.snapshots = s }
        if let p = await portsTask {
            self.portsEnabled = p.enabled
            self.allPorts = p.ports
        }

        let targetOrgId = currentOrg?.id
        if let u = try? await client.fetchUsage(orgId: targetOrgId) {
            self.usage = u
        }
        if let mu = try? await client.fetchMachineUsage(orgId: targetOrgId) {
            self.machineUsages = mu.machines
        }
        if let targetOrgId {
            if let sec = try? await client.fetchOrgSecrets(orgId: targetOrgId) {
                self.secrets = sec
            }
            if let wh = try? await client.fetchOrgWebhooks(orgId: targetOrgId) {
                self.webhooks = wh.items
                self.webhookEventTypes = wh.eventTypes
            }
        }
    }

    // MARK: - Tracked Lifecycle Operations

    public func trackOperation(_ initialOp: OperationItem, successMessage: String) {
        activeOperations[initialOp.machineId] = initialOp
        guard let client else { return }

        Task {
            do {
                let finalOp = try await client.waitForOperation(id: initialOp.id) { progressOp in
                    self.activeOperations[initialOp.machineId] = progressOp
                }
                self.activeOperations.removeValue(forKey: finalOp.machineId)
                self.showToast(.success, successMessage)
                await self.refreshAll(silent: true)
            } catch {
                self.activeOperations.removeValue(forKey: initialOp.machineId)
                self.showToast(.error, error.localizedDescription)
                await self.refreshMachinesAndUsageSilently()
            }
        }
    }

    public func startMachine(_ machine: MachineItem) async {
        guard let client else { return }
        do {
            let op = try await client.startMachine(id: machine.id)
            showToast(.info, "正在启动沙盒 \(machine.name)…")
            trackOperation(op, successMessage: "沙盒 \(machine.name) 已启动")
            await refreshMachinesAndUsageSilently()
        } catch {
            showToast(.error, error.localizedDescription)
        }
    }

    public func stopMachine(_ machine: MachineItem, now: Bool = false) async {
        guard let client else { return }
        do {
            let op = try await client.stopMachine(id: machine.id, now: now)
            showToast(.info, "正在停止沙盒 \(machine.name)…")
            trackOperation(op, successMessage: "沙盒 \(machine.name) 已停止")
            await refreshMachinesAndUsageSilently()
        } catch {
            showToast(.error, error.localizedDescription)
        }
    }

    public func suspendMachine(_ machine: MachineItem) async {
        guard let client else { return }
        do {
            let op = try await client.suspendMachine(id: machine.id)
            showToast(.info, "正在暂停沙盒 \(machine.name)…")
            trackOperation(op, successMessage: "沙盒 \(machine.name) 已暂停并保留内存状态")
            await refreshMachinesAndUsageSilently()
        } catch {
            showToast(.error, error.localizedDescription)
        }
    }

    public func resumeMachine(_ machine: MachineItem) async {
        guard let client else { return }
        do {
            let op = try await client.resumeMachine(id: machine.id)
            showToast(.info, "正在恢复沙盒 \(machine.name)…")
            trackOperation(op, successMessage: "沙盒 \(machine.name) 已恢复运行")
            await refreshMachinesAndUsageSilently()
        } catch {
            showToast(.error, error.localizedDescription)
        }
    }

    public func restartMachine(_ machine: MachineItem) async {
        guard let client else { return }
        do {
            showToast(.info, "正在重启沙盒 \(machine.name)…")
            if machine.state == .suspended {
                let resOp = try await client.resumeMachine(id: machine.id)
                _ = try await client.waitForOperation(id: resOp.id)
            }
            if machine.state == .running || machine.state == .suspended {
                let stopOp = try await client.stopMachine(id: machine.id)
                activeOperations[machine.id] = stopOp
                _ = try await client.waitForOperation(id: stopOp.id)
            }
            let startOp = try await client.startMachine(id: machine.id)
            trackOperation(startOp, successMessage: "沙盒 \(machine.name) 重启完成")
            await refreshMachinesAndUsageSilently()
        } catch {
            activeOperations.removeValue(forKey: machine.id)
            showToast(.error, error.localizedDescription)
        }
    }

    public func deleteMachine(_ machine: MachineItem) async {
        guard let client else { return }
        do {
            let op = try await client.deleteMachine(id: machine.id, confirmValue: machine.id)
            showToast(.info, "正在删除沙盒 \(machine.name)…")
            if selectedMachineID == machine.id {
                selectedMachineID = machines.first(where: { $0.id != machine.id })?.id
            }
            trackOperation(op, successMessage: "沙盒 \(machine.name) 已删除")
            await refreshMachinesAndUsageSilently()
        } catch {
            showToast(.error, error.localizedDescription)
        }
    }

    public func forkMachine(_ machine: MachineItem, newName: String?) async {
        guard let client else { return }
        do {
            let cleanName = newName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let req = ForkMachineRequest(name: (cleanName?.isEmpty == false) ? cleanName : nil)
            let op = try await client.forkMachine(id: machine.id, request: req)
            showToast(.info, "正在克隆沙盒 \(machine.name)…")
            trackOperation(op, successMessage: "沙盒克隆完成")
            await refreshMachinesAndUsageSilently()
        } catch {
            showToast(.error, error.localizedDescription)
        }
    }

    public func openQuickSSH(for machine: MachineItem) async {
        guard let client else { return }
        do {
            let token = try await client.createSSHToken(
                machineId: machine.id,
                request: CreateSSHTokenRequest(name: "mac-panel-\(Int(Date().timeIntervalSince1970))", ttlSeconds: 28800)
            )
            try TerminalLauncher.openSSHCommand(
                token.command,
                machineName: machine.name,
                preferredApp: preferredTerminal
            )
            showToast(.success, "已在终端打开 SSH（命令同时已复制到剪贴板）")
        } catch {
            showToast(.error, error.localizedDescription)
        }
    }

    // MARK: - MCP Server Control & Playground

    public var mcpExecutablePath: String {
        if let exec = Bundle.main.executablePath, !exec.isEmpty {
            return exec
        }
        return "/Applications/InstaBox Manager.app/Contents/MacOS/InstaBoxManager"
    }

    public var mcpHTTPEndpoint: String {
        "http://127.0.0.1:\(mcpServerPort)/mcp"
    }

    public var activeRawAPIKeyForMCPConfig: String? {
        guard let activeProfileID else { return nil }
        return KeychainService.loadAPIKey(for: activeProfileID)
    }

    private func setupMCPEngine() {
        let engine = MCPServerEngine(
            clientProvider: { MCPServerEngine.defaultClientProvider() },
            activityHandler: { [weak self] entry in
                let target = self
                await MainActor.run {
                    guard let target else { return }
                    target.mcpLogs.insert(entry, at: 0)
                    if target.mcpLogs.count > 80 {
                        target.mcpLogs.removeLast(target.mcpLogs.count - 80)
                    }
                }
            }
        )
        self.mcpEngine = engine
        self.mcpHTTPServer = MCPHTTPServer(engine: engine)
    }

    public func startMCPServer(silent: Bool = false) {
        if mcpHTTPServer == nil {
            setupMCPEngine()
        }
        guard let server = mcpHTTPServer else { return }
        mcpServerError = nil
        do {
            try server.start(port: UInt16(mcpServerPort)) { [weak self] running, errMsg in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.mcpServerRunning = running
                    self.mcpServerError = errMsg
                    if let errMsg, !silent {
                        self.showToast(.error, errMsg)
                    } else if running && !silent {
                        self.showToast(.success, "本地 HTTP MCP 服务已启动（127.0.0.1:\(self.mcpServerPort)/mcp）")
                    }
                }
            }
        } catch {
            mcpServerRunning = false
            mcpServerError = error.localizedDescription
            if !silent {
                showToast(.error, "启动 MCP 服务失败：\(error.localizedDescription)")
            }
        }
    }

    public func stopMCPServer(silent: Bool = false) {
        mcpHTTPServer?.stop()
        mcpServerRunning = false
        if !silent {
            showToast(.info, "本地 HTTP MCP 服务已停止")
        }
    }

    public func toggleMCPServer() {
        if mcpServerRunning {
            stopMCPServer()
        } else {
            startMCPServer()
        }
    }

    public func clearMCPLogs() {
        mcpLogs.removeAll()
    }

    public func runMCPPlayground(toolName: String, argumentsJSON: String) async -> String {
        if mcpEngine == nil {
            setupMCPEngine()
        }
        guard let engine = mcpEngine else { return "{}" }

        var argsObj: [String: Any] = [:]
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            guard let data = trimmed.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "{\"error\": \"参数 JSON 格式无效，请传入合法 JSON 对象（如 {}）\"}"
            }
            argsObj = parsed
        }

        let rpcReq: [String: Any] = [
            "jsonrpc": "2.0",
            "id": Int(Date().timeIntervalSince1970),
            "method": "tools/call",
            "params": [
                "name": toolName,
                "arguments": argsObj
            ]
        ]

        guard let resp = await engine.handleRequestObject(rpcReq, transport: "Playground"),
              let outData = try? JSONSerialization.data(withJSONObject: resp, options: [.prettyPrinted, .sortedKeys]),
              let outStr = String(data: outData, encoding: .utf8) else {
            return "{}"
        }
        return outStr
    }
}
