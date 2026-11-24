import Foundation

// MARK: - MCP Activity Log Model

public struct MCPLogEntry: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let timestamp: Date
    public let transport: String // "HTTP", "Playground", "Stdio"
    public let method: String
    public let detail: String
    public let durationMs: Int
    public let isError: Bool
    public let responsePreview: String

    public init(
        timestamp: Date = Date(),
        transport: String,
        method: String,
        detail: String,
        durationMs: Int,
        isError: Bool,
        responsePreview: String
    ) {
        self.timestamp = timestamp
        self.transport = transport
        self.method = method
        self.detail = detail
        self.durationMs = durationMs
        self.isError = isError
        self.responsePreview = responsePreview
    }
}

public struct MCPToolDescriptor: Identifiable, Sendable {
    public let name: String
    public let summary: String
    public let category: String
    public let parametersSummary: String

    public var id: String { name }
}

// MARK: - Native MCP JSON-RPC 2.0 Engine

public final class MCPServerEngine: Sendable {
    public static let serverName = "instabox-manager"
    public static let serverVersion = "1.0.0"
    public static let defaultProtocolVersion = "2025-03-26"

    private let clientProvider: @Sendable () -> InstaBoxClient?
    private let activityHandler: (@Sendable (MCPLogEntry) async -> Void)?

    public init(
        clientProvider: @escaping @Sendable () -> InstaBoxClient? = { MCPServerEngine.defaultClientProvider() },
        activityHandler: (@Sendable (MCPLogEntry) async -> Void)? = nil
    ) {
        self.clientProvider = clientProvider
        self.activityHandler = activityHandler
    }

    /// Resolves an `InstaBoxClient` from `INSTABOX_API_KEY` env override first,
    /// falling back to the active workspace stored securely in macOS Keychain.
    public static func defaultClientProvider() -> InstaBoxClient? {
        let env = ProcessInfo.processInfo.environment
        if let rawKey = env["INSTABOX_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawKey.isEmpty {
            let base = env["INSTABOX_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return InstaBoxClient(
                baseURL: (base?.isEmpty == false) ? base! : "https://api.instabox.sh",
                apiKey: rawKey
            )
        }

        let profiles = KeychainService.loadProfiles()
        if let activeId = KeychainService.loadActiveProfileID(),
           let profile = profiles.first(where: { $0.id == activeId }),
           let key = KeychainService.loadAPIKey(for: profile.id),
           !key.isEmpty {
            return InstaBoxClient(baseURL: profile.normalizedBaseURL, apiKey: key)
        }

        for profile in profiles {
            if let key = KeychainService.loadAPIKey(for: profile.id), !key.isEmpty {
                return InstaBoxClient(baseURL: profile.normalizedBaseURL, apiKey: key)
            }
        }
        return nil
    }

    public static let toolCatalog: [MCPToolDescriptor] = [
        MCPToolDescriptor(name: "instabox_get_usage", summary: "获取当前工作区配额、用量、余额与限制", category: "工作区", parametersSummary: "无必填参数"),
        MCPToolDescriptor(name: "instabox_list_machines", summary: "列出全部云端沙盒（支持按状态筛选）", category: "沙盒实例", parametersSummary: "state?: running|suspended|stopped"),
        MCPToolDescriptor(name: "instabox_get_machine", summary: "获取单台沙盒的详细状态、规格与存储信息", category: "沙盒实例", parametersSummary: "machine_id"),
        MCPToolDescriptor(name: "instabox_create_machine", summary: "基于官方模板或快照创建新沙盒", category: "沙盒实例", parametersSummary: "name?, template_id?, snapshot_id?, wait_ready?"),
        MCPToolDescriptor(name: "instabox_machine_lifecycle", summary: "启停、暂停、恢复、唤醒、重启、克隆或删除沙盒", category: "沙盒实例", parametersSummary: "machine_id, action, confirm?, wait?"),
        MCPToolDescriptor(name: "instabox_exec_command", summary: "在沙盒内执行 Bash 命令并返回 stdout/stderr/exitCode", category: "命令执行", parametersSummary: "machine_id, cmd, cwd?, stdin?, timeout_seconds?"),
        MCPToolDescriptor(name: "instabox_list_files", summary: "浏览沙盒目录文件列表", category: "文件管理", parametersSummary: "machine_id, path?"),
        MCPToolDescriptor(name: "instabox_read_file", summary: "读取沙盒内文本文件内容", category: "文件管理", parametersSummary: "machine_id, path"),
        MCPToolDescriptor(name: "instabox_write_file", summary: "写入或创建沙盒内文本文件（自动创建父目录）", category: "文件管理", parametersSummary: "machine_id, path, content, mode?"),
        MCPToolDescriptor(name: "instabox_list_snapshots", summary: "列出工作区全部快照镜像", category: "快照镜像", parametersSummary: "无必填参数"),
        MCPToolDescriptor(name: "instabox_create_snapshot", summary: "将指定沙盒保存为快照", category: "快照镜像", parametersSummary: "machine_id, name, description?"),
        MCPToolDescriptor(name: "instabox_restore_snapshot", summary: "将沙盒磁盘原地回滚到指定快照", category: "快照镜像", parametersSummary: "machine_id, snapshot_id, wait?"),
        MCPToolDescriptor(name: "instabox_list_ports", summary: "查看工作区或指定沙盒已发布的公网/私密端口", category: "网络与 SSH", parametersSummary: "machine_id?"),
        MCPToolDescriptor(name: "instabox_publish_port", summary: "暴露沙盒内部端口为公开或私密 HTTPS URL", category: "网络与 SSH", parametersSummary: "machine_id, port, access?, protocol?, name?"),
        MCPToolDescriptor(name: "instabox_unpublish_port", summary: "取消发布沙盒端口映射", category: "网络与 SSH", parametersSummary: "machine_id, port"),
        MCPToolDescriptor(name: "instabox_create_ssh_token", summary: "签发沙盒免密 SSH / Mosh 连接命令", category: "网络与 SSH", parametersSummary: "machine_id, name?, ttl_seconds?"),
        MCPToolDescriptor(name: "instabox_machine_diagnostics", summary: "聚合获取沙盒 CPU/内存指标、磁盘、进程与控制台日志", category: "监控诊断", parametersSummary: "machine_id, tail?"),
        MCPToolDescriptor(name: "instabox_clipboard_sync", summary: "推送文本到云端桌面剪贴板或读取云端剪贴板", category: "远程桌面", parametersSummary: "machine_id, direction: push|pull, text?")
    ]

    // MARK: - Raw JSON-RPC Entry Point

    /// Processes a single JSON-RPC 2.0 request (or batch array) and returns encoded JSON data.
    /// Returns `nil` when the message is a JSON-RPC notification (no `id`) that requires no response.
    public func handleRawJSON(_ data: Data, transport: String = "Stdio") async -> Data? {
        guard let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return encodeJSON(jsonRPCError(id: NSNull(), code: -32700, message: "Parse error: invalid JSON"))
        }

        if let batch = parsed as? [[String: Any]] {
            var responses: [[String: Any]] = []
            for item in batch {
                if let resp = await handleRequestObject(item, transport: transport) {
                    responses.append(resp)
                }
            }
            return responses.isEmpty ? nil : encodeJSON(responses)
        }

        guard let obj = parsed as? [String: Any] else {
            return encodeJSON(jsonRPCError(id: NSNull(), code: -32600, message: "Invalid Request"))
        }

        guard let response = await handleRequestObject(obj, transport: transport) else {
            return nil
        }
        return encodeJSON(response)
    }

    public func handleRequestObject(_ req: [String: Any], transport: String = "Stdio") async -> [String: Any]? {
        let id = req["id"]
        let isNotification = (id == nil)

        guard let method = req["method"] as? String else {
            return isNotification ? nil : jsonRPCError(id: id ?? NSNull(), code: -32600, message: "Missing method")
        }

        let params = req["params"] as? [String: Any] ?? [:]
        let started = Date()

        // Notifications do not return responses
        if method.hasPrefix("notifications/") {
            await recordActivity(
                transport: transport,
                method: method,
                detail: "notification",
                started: started,
                isError: false,
                preview: "(ack)"
            )
            return nil
        }

        let responseId = id ?? NSNull()

        switch method {
        case "initialize":
            let clientVersion = params["protocolVersion"] as? String
            let negotiated = (clientVersion == "2024-11-05" || clientVersion == "2025-03-26")
                ? clientVersion!
                : Self.defaultProtocolVersion
            let result: [String: Any] = [
                "protocolVersion": negotiated,
                "capabilities": [
                    "tools": ["listChanged": false],
                    "resources": ["subscribe": false, "listChanged": false]
                ],
                "serverInfo": [
                    "name": Self.serverName,
                    "version": Self.serverVersion
                ],
                "instructions": "InstaBox Manager MCP Server: manage InstaBox cloud sandboxes, execute commands, browse/edit files, manage snapshots, expose HTTPS ports, issue SSH tokens, inspect diagnostics, and sync desktop clipboards."
            ]
            await recordActivity(transport: transport, method: method, detail: "protocol \(negotiated)", started: started, isError: false, preview: "initialized (\(Self.toolCatalog.count) tools)")
            return jsonRPCResult(id: responseId, result: result)

        case "ping":
            await recordActivity(transport: transport, method: method, detail: "health ping", started: started, isError: false, preview: "{}")
            return jsonRPCResult(id: responseId, result: [String: Any]())

        case "tools/list":
            let tools = Self.toolSchemas()
            await recordActivity(transport: transport, method: method, detail: "\(tools.count) tools", started: started, isError: false, preview: "returned \(tools.count) tool definitions")
            return jsonRPCResult(id: responseId, result: ["tools": tools])

        case "tools/call":
            guard let toolName = params["name"] as? String else {
                return jsonRPCError(id: responseId, code: -32602, message: "Missing tool name in params.name")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            let (text, isError) = await executeTool(name: toolName, arguments: args)
            let result: [String: Any] = [
                "content": [
                    ["type": "text", "text": text]
                ],
                "isError": isError
            ]
            await recordActivity(
                transport: transport,
                method: "tools/call",
                detail: toolName,
                started: started,
                isError: isError,
                preview: String(text.prefix(400))
            )
            return jsonRPCResult(id: responseId, result: result)

        case "resources/list":
            let resources: [[String: Any]] = [
                [
                    "uri": "instabox://workspace/usage",
                    "name": "工作区配额与费用",
                    "description": "当前 InstaBox 工作区的沙盒/快照/存储配额与本月账单统计",
                    "mimeType": "application/json"
                ],
                [
                    "uri": "instabox://machines",
                    "name": "沙盒实例列表",
                    "description": "当前工作区全部云端沙盒实例及实时状态",
                    "mimeType": "application/json"
                ],
                [
                    "uri": "instabox://snapshots",
                    "name": "快照镜像列表",
                    "description": "当前工作区所有已保存的沙盒快照",
                    "mimeType": "application/json"
                ],
                [
                    "uri": "instabox://ports",
                    "name": "已发布公网端口",
                    "description": "当前工作区所有沙盒暴露的 HTTPS 域名与端口映射",
                    "mimeType": "application/json"
                ]
            ]
            await recordActivity(transport: transport, method: method, detail: "\(resources.count) resources", started: started, isError: false, preview: "listed \(resources.count) resources")
            return jsonRPCResult(id: responseId, result: ["resources": resources])

        case "resources/read":
            guard let uri = params["uri"] as? String else {
                return jsonRPCError(id: responseId, code: -32602, message: "Missing resource uri")
            }
            do {
                let text = try await readResource(uri: uri)
                let result: [String: Any] = [
                    "contents": [
                        [
                            "uri": uri,
                            "mimeType": "application/json",
                            "text": text
                        ]
                    ]
                ]
                await recordActivity(transport: transport, method: method, detail: uri, started: started, isError: false, preview: String(text.prefix(320)))
                return jsonRPCResult(id: responseId, result: result)
            } catch {
                await recordActivity(transport: transport, method: method, detail: uri, started: started, isError: true, preview: error.localizedDescription)
                return jsonRPCError(id: responseId, code: -32002, message: error.localizedDescription)
            }

        case "prompts/list":
            return jsonRPCResult(id: responseId, result: ["prompts": [[String: Any]]()])

        default:
            await recordActivity(transport: transport, method: method, detail: "method not found", started: started, isError: true, preview: "Method not found: \(method)")
            return isNotification ? nil : jsonRPCError(id: responseId, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: - Tool Execution

    private func executeTool(name: String, arguments args: [String: Any]) async -> (String, Bool) {
        guard let client = clientProvider() else {
            return ("尚未配置 InstaBox API Key：请先在 InstaBox Manager 桌面端登录连接工作区，或在 MCP 环境变量中设置 INSTABOX_API_KEY。", true)
        }

        do {
            switch name {
            case "instabox_get_usage":
                async let orgs = try? client.fetchOrgs()
                async let me = try? client.fetchMe()
                let resolvedOrgs = await orgs ?? []
                let resolvedMe = await me
                let usage = try await client.fetchUsage(orgId: resolvedOrgs.first?.id)
                let summary: [String: Any] = [
                    "user": resolvedMe?.login ?? "",
                    "org": usage.org?.name ?? resolvedOrgs.first?.name ?? "",
                    "tier": usage.org?.tier ?? resolvedOrgs.first?.tier ?? "",
                    "machines": usage.machines,
                    "maxMachines": usage.limits.maxMachines,
                    "snapshots": usage.snapshots,
                    "maxSnapshots": usage.limits.maxSnapshots,
                    "storedBytes": usage.storedBytes ?? 0,
                    "maxStoredGiB": usage.limits.maxStoredGiB,
                    "allocatedDiskGiB": usage.allocatedDiskGiB ?? 0,
                    "costUSD": usage.cost?.costUSD ?? 0,
                    "creditsUSD": usage.cost?.creditsUSD ?? 0
                ]
                return (prettyJSONObject(summary), false)

            case "instabox_list_machines":
                var machines = try await client.fetchMachines()
                if let filterState = (args["state"] as? String)?.lowercased(), !filterState.isEmpty {
                    machines = machines.filter { $0.state.rawValue.lowercased() == filterState }
                }
                return (try prettyEncode(machines), false)

            case "instabox_get_machine":
                let id = try requireString(args, "machine_id")
                let machine = try await client.fetchMachine(id: id)
                return (try prettyEncode(machine), false)

            case "instabox_create_machine":
                let nameArg = args["name"] as? String
                let templateId = args["template_id"] as? String
                let snapshotId = args["snapshot_id"] as? String
                let desiredState = (args["desired_state"] as? String) ?? "running"
                let waitReady = (args["wait_ready"] as? Bool) ?? true
                let req = CreateMachineRequest(
                    name: nameArg,
                    templateId: snapshotId == nil ? (templateId ?? "agent-browser") : nil,
                    snapshotId: snapshotId,
                    vcpus: args["vcpus"] as? Int,
                    memMiB: args["mem_mib"] as? Int,
                    desiredState: desiredState,
                    autoSuspendAfterSeconds: args["auto_suspend_seconds"] as? Int
                )
                let op = try await client.createMachine(req)
                if waitReady {
                    let finalOp = try await client.waitForOperation(id: op.id)
                    let machine = try? await client.fetchMachine(id: finalOp.machineId)
                    if let machine {
                        return (try prettyEncode(machine), false)
                    }
                    return (try prettyEncode(finalOp), false)
                }
                return (try prettyEncode(op), false)

            case "instabox_machine_lifecycle":
                let id = try requireString(args, "machine_id")
                let action = try requireString(args, "action").lowercased()
                let wait = (args["wait"] as? Bool) ?? true

                switch action {
                case "wake":
                    let machine = try await client.wakeMachine(id: id)
                    return (try prettyEncode(machine), false)
                case "start":
                    let op = try await client.startMachine(id: id)
                    return (try prettyEncode(wait ? try await client.waitForOperation(id: op.id) : op), false)
                case "stop":
                    let now = (args["now"] as? Bool) ?? false
                    let op = try await client.stopMachine(id: id, now: now)
                    return (try prettyEncode(wait ? try await client.waitForOperation(id: op.id) : op), false)
                case "suspend", "pause":
                    let op = try await client.suspendMachine(id: id)
                    return (try prettyEncode(wait ? try await client.waitForOperation(id: op.id) : op), false)
                case "resume":
                    let op = try await client.resumeMachine(id: id)
                    return (try prettyEncode(wait ? try await client.waitForOperation(id: op.id) : op), false)
                case "restart":
                    let m = try await client.fetchMachine(id: id)
                    if m.state == .suspended {
                        let rOp = try await client.resumeMachine(id: id)
                        _ = try await client.waitForOperation(id: rOp.id)
                    }
                    if m.state == .running || m.state == .suspended {
                        let sOp = try await client.stopMachine(id: id)
                        _ = try await client.waitForOperation(id: sOp.id)
                    }
                    let startOp = try await client.startMachine(id: id)
                    return (try prettyEncode(wait ? try await client.waitForOperation(id: startOp.id) : startOp), false)
                case "fork":
                    let newName = args["new_name"] as? String
                    let op = try await client.forkMachine(id: id, request: ForkMachineRequest(name: newName))
                    return (try prettyEncode(wait ? try await client.waitForOperation(id: op.id) : op), false)
                case "delete":
                    guard (args["confirm"] as? Bool) == true else {
                        return ("安全拦截：删除沙盒属于不可逆操作，必须显式传入 arguments.confirm = true。", true)
                    }
                    let op = try await client.deleteMachine(id: id, confirmValue: id)
                    return (try prettyEncode(wait ? try await client.waitForOperation(id: op.id) : op), false)
                default:
                    return ("不支持的 action: \(action)（支持 start/stop/suspend/resume/wake/restart/fork/delete）", true)
                }

            case "instabox_exec_command":
                let id = try requireString(args, "machine_id")
                let cmd = try requireString(args, "cmd")
                let cwd = args["cwd"] as? String
                let stdinStr = args["stdin"] as? String
                let timeout = args["timeout_seconds"] as? Int ?? 60
                let res = try await client.execCommand(
                    machineId: id,
                    request: ExecRequest(cmd: cmd, cwd: cwd, stdin: stdinStr, timeoutSeconds: timeout)
                )
                return (try prettyEncode(res), res.exitCode != 0)

            case "instabox_list_files":
                let id = try requireString(args, "machine_id")
                let path = (args["path"] as? String)?.isEmpty == false ? (args["path"] as! String) : "/data/home"
                let res = try await client.fetchFiles(machineId: id, path: path)
                return (try prettyEncode(res), false)

            case "instabox_read_file":
                let id = try requireString(args, "machine_id")
                let path = try requireString(args, "path")
                let res = try await client.fetchFiles(machineId: id, path: path)
                if res.binary == true {
                    return ("文件 \(path) 为二进制文件（\(res.size) 字节），不支持直接作为文本返回。", true)
                }
                return (res.content ?? "", false)

            case "instabox_write_file":
                let id = try requireString(args, "machine_id")
                let path = try requireString(args, "path")
                let content = try requireString(args, "content")
                let mode = args["mode"] as? String
                let res = try await client.uploadFile(
                    machineId: id,
                    remotePath: path,
                    data: Data(content.utf8),
                    mode: mode,
                    parents: true
                )
                return (try prettyEncode(res), false)

            case "instabox_list_snapshots":
                let snaps = try await client.fetchSnapshots()
                return (try prettyEncode(snaps), false)

            case "instabox_create_snapshot":
                let id = try requireString(args, "machine_id")
                let snapName = try requireString(args, "name")
                let desc = args["description"] as? String
                let snap = try await client.createSnapshot(
                    machineId: id,
                    request: CreateSnapshotRequest(name: snapName, description: desc)
                )
                return (try prettyEncode(snap), false)

            case "instabox_restore_snapshot":
                let id = try requireString(args, "machine_id")
                let snapshotId = try requireString(args, "snapshot_id")
                let wait = (args["wait"] as? Bool) ?? true
                let op = try await client.restoreMachine(
                    id: id,
                    request: RestoreMachineRequest(snapshotId: snapshotId, desiredState: "running")
                )
                return (try prettyEncode(wait ? try await client.waitForOperation(id: op.id) : op), false)

            case "instabox_list_ports":
                if let machineId = args["machine_id"] as? String, !machineId.isEmpty {
                    let res = try await client.fetchMachinePorts(machineId: machineId)
                    return (try prettyEncode(res), false)
                } else {
                    let res = try await client.fetchAllPorts()
                    return (try prettyEncode(res), false)
                }

            case "instabox_publish_port":
                let id = try requireString(args, "machine_id")
                guard let port = args["port"] as? Int, (1...65535).contains(port) else {
                    return ("参数 port 必须为 1–65535 的整数。", true)
                }
                let req = PublishPortRequest(
                    port: port,
                    name: args["name"] as? String,
                    access: (args["access"] as? String) ?? "public",
                    protocol: (args["protocol"] as? String) ?? "http"
                )
                let item = try await client.publishPort(machineId: id, request: req)
                return (try prettyEncode(item), false)

            case "instabox_unpublish_port":
                let id = try requireString(args, "machine_id")
                guard let port = args["port"] as? Int else {
                    return ("缺少整数参数 port。", true)
                }
                try await client.unpublishPort(machineId: id, port: port)
                return ("已取消发布沙盒 \(id) 的端口 \(port)。", false)

            case "instabox_create_ssh_token":
                let id = try requireString(args, "machine_id")
                let tokenName = (args["name"] as? String) ?? "mcp-agent"
                let ttl = args["ttl_seconds"] as? Int ?? 3600
                let res = try await client.createSSHToken(
                    machineId: id,
                    request: CreateSSHTokenRequest(name: tokenName, ttlSeconds: ttl)
                )
                return (try prettyEncode(res), false)

            case "instabox_machine_diagnostics":
                let id = try requireString(args, "machine_id")
                let tail = args["tail"] as? Int ?? 120
                async let metrics = try? client.fetchMachineMetrics(machineId: id)
                async let disk = try? client.fetchMachineDisk(machineId: id)
                async let procs = try? client.fetchMachineProcesses(machineId: id, all: true)
                async let logs = try? client.fetchMachineLogs(machineId: id, tail: tail)

                let payload: [String: Any] = [
                    "machineId": id,
                    "latestMetric": (await metrics?.metrics.last).flatMap { try? toJSONObject($0) } ?? NSNull(),
                    "disk": (await disk).flatMap { try? toJSONObject($0) } ?? NSNull(),
                    "processCount": await procs?.processes.count ?? 0,
                    "topProcesses": (await procs?.processes.prefix(15)).map { Array($0) }.flatMap { try? toJSONObject($0) } ?? [],
                    "consoleLogsTail": await logs?.console ?? ""
                ]
                return (prettyJSONObject(payload), false)

            case "instabox_clipboard_sync":
                let id = try requireString(args, "machine_id")
                let direction = try requireString(args, "direction").lowercased()
                if direction == "push" {
                    let text = try requireString(args, "text")
                    try await SandboxClipboardSync.pushToSandbox(
                        client: client,
                        machineId: id,
                        text: text,
                        autoInstallIfMissing: true
                    )
                    return ("已将 \(text.count) 字符写入沙盒 \(id) 桌面剪贴板。", false)
                } else if direction == "pull" {
                    let text = try await SandboxClipboardSync.pullFromSandbox(
                        client: client,
                        machineId: id,
                        autoInstallIfMissing: true
                    )
                    return (text, false)
                } else {
                    return ("参数 direction 必须为 push 或 pull。", true)
                }

            default:
                return ("未知 MCP 工具：\(name)", true)
            }
        } catch {
            return (error.localizedDescription, true)
        }
    }

    // MARK: - Resources

    private func readResource(uri: String) async throws -> String {
        guard let client = clientProvider() else {
            throw InstaBoxError.missingAPIKey
        }
        switch uri {
        case "instabox://workspace/usage":
            let orgs = (try? await client.fetchOrgs()) ?? []
            let usage = try await client.fetchUsage(orgId: orgs.first?.id)
            return try prettyEncode(usage)
        case "instabox://machines":
            return try prettyEncode(try await client.fetchMachines())
        case "instabox://snapshots":
            return try prettyEncode(try await client.fetchSnapshots())
        case "instabox://ports":
            return try prettyEncode(try await client.fetchAllPorts())
        default:
            throw InstaBoxError.networkError("未找到资源 URI: \(uri)")
        }
    }

    // MARK: - Tool Schemas

    private static func toolSchemas() -> [[String: Any]] {
        func prop(_ type: String, _ desc: String, enumValues: [String]? = nil) -> [String: Any] {
            var d: [String: Any] = ["type": type, "description": desc]
            if let enumValues { d["enum"] = enumValues }
            return d
        }

        func tool(_ name: String, _ desc: String, properties: [String: Any] = [:], required: [String] = []) -> [String: Any] {
            var schema: [String: Any] = [
                "type": "object",
                "properties": properties
            ]
            if !required.isEmpty {
                schema["required"] = required
            }
            return [
                "name": name,
                "description": desc,
                "inputSchema": schema
            ]
        }

        return [
            tool("instabox_get_usage", "Get current InstaBox workspace quotas, limits, storage usage, and billing summary."),
            tool(
                "instabox_list_machines",
                "List all InstaBox cloud sandboxes in the active workspace.",
                properties: [
                    "state": prop("string", "Optional filter by state", enumValues: ["running", "suspended", "stopped"])
                ]
            ),
            tool(
                "instabox_get_machine",
                "Get full details of a single InstaBox sandbox by ID.",
                properties: ["machine_id": prop("string", "Sandbox machine ID (e.g. m_...)")],
                required: ["machine_id"]
            ),
            tool(
                "instabox_create_machine",
                "Create a new InstaBox cloud sandbox from an official template or snapshot.",
                properties: [
                    "name": prop("string", "Optional sandbox name"),
                    "template_id": prop("string", "Template ID (default: agent-browser, e.g. android, omarchy, ci, universal)"),
                    "snapshot_id": prop("string", "Optional ready snapshot ID to clone from"),
                    "vcpus": prop("integer", "Optional vCPU count (paid tiers)"),
                    "mem_mib": prop("integer", "Optional memory in MiB (paid tiers)"),
                    "desired_state": prop("string", "Initial state", enumValues: ["running", "stopped"]),
                    "auto_suspend_seconds": prop("integer", "Idle auto-pause seconds (0 = always on for paid tiers)"),
                    "wait_ready": prop("boolean", "Wait until create operation finishes (default: true)")
                ]
            ),
            tool(
                "instabox_machine_lifecycle",
                "Perform a lifecycle action on a sandbox (start, stop, suspend, resume, wake, restart, fork, delete).",
                properties: [
                    "machine_id": prop("string", "Target sandbox ID"),
                    "action": prop("string", "Lifecycle action", enumValues: ["start", "stop", "suspend", "resume", "wake", "restart", "fork", "delete"]),
                    "new_name": prop("string", "Optional new sandbox name when action=fork"),
                    "now": prop("boolean", "Force immediate stop when action=stop"),
                    "confirm": prop("boolean", "Must be true when action=delete"),
                    "wait": prop("boolean", "Wait for operation completion (default: true)")
                ],
                required: ["machine_id", "action"]
            ),
            tool(
                "instabox_exec_command",
                "Execute a bash command inside a running InstaBox sandbox and return stdout, stderr, and exitCode.",
                properties: [
                    "machine_id": prop("string", "Target sandbox ID"),
                    "cmd": prop("string", "Shell command string to execute"),
                    "cwd": prop("string", "Optional working directory (e.g. /data/home)"),
                    "stdin": prop("string", "Optional UTF-8 stdin payload"),
                    "timeout_seconds": prop("integer", "Execution timeout in seconds (default: 60)")
                ],
                required: ["machine_id", "cmd"]
            ),
            tool(
                "instabox_list_files",
                "List files and directories inside a sandbox path.",
                properties: [
                    "machine_id": prop("string", "Target sandbox ID"),
                    "path": prop("string", "Directory path (default: /data/home)")
                ],
                required: ["machine_id"]
            ),
            tool(
                "instabox_read_file",
                "Read UTF-8 text content of a file inside a sandbox.",
                properties: [
                    "machine_id": prop("string", "Target sandbox ID"),
                    "path": prop("string", "Absolute file path inside sandbox")
                ],
                required: ["machine_id", "path"]
            ),
            tool(
                "instabox_write_file",
                "Create or overwrite a UTF-8 text file inside a sandbox (creates parent directories automatically).",
                properties: [
                    "machine_id": prop("string", "Target sandbox ID"),
                    "path": prop("string", "Absolute destination file path inside sandbox"),
                    "content": prop("string", "UTF-8 file contents to write"),
                    "mode": prop("string", "Optional octal file permission mode (e.g. 0755)")
                ],
                required: ["machine_id", "path", "content"]
            ),
            tool("instabox_list_snapshots", "List all saved sandbox snapshots in the workspace."),
            tool(
                "instabox_create_snapshot",
                "Save a snapshot of an InstaBox sandbox.",
                properties: [
                    "machine_id": prop("string", "Source sandbox ID"),
                    "name": prop("string", "Snapshot name"),
                    "description": prop("string", "Optional snapshot description")
                ],
                required: ["machine_id", "name"]
            ),
            tool(
                "instabox_restore_snapshot",
                "Restore a sandbox disk in-place from a ready snapshot.",
                properties: [
                    "machine_id": prop("string", "Target sandbox ID"),
                    "snapshot_id": prop("string", "Ready snapshot ID"),
                    "wait": prop("boolean", "Wait for restore completion (default: true)")
                ],
                required: ["machine_id", "snapshot_id"]
            ),
            tool(
                "instabox_list_ports",
                "List published public/private HTTPS ports for all sandboxes or a specific sandbox.",
                properties: ["machine_id": prop("string", "Optional sandbox ID to filter by")]
            ),
            tool(
                "instabox_publish_port",
                "Expose an internal sandbox port as a public or private HTTPS URL.",
                properties: [
                    "machine_id": prop("string", "Target sandbox ID"),
                    "port": prop("integer", "Internal TCP/HTTP port (1–65535)"),
                    "name": prop("string", "Optional display label"),
                    "access": prop("string", "Access control", enumValues: ["public", "private"]),
                    "protocol": prop("string", "Protocol", enumValues: ["http", "tcp"])
                ],
                required: ["machine_id", "port"]
            ),
            tool(
                "instabox_unpublish_port",
                "Remove a published port mapping from a sandbox.",
                properties: [
                    "machine_id": prop("string", "Target sandbox ID"),
                    "port": prop("integer", "Published port number to remove")
                ],
                required: ["machine_id", "port"]
            ),
            tool(
                "instabox_create_ssh_token",
                "Issue a temporary passwordless SSH / Mosh connection command for a sandbox.",
                properties: [
                    "machine_id": prop("string", "Target sandbox ID"),
                    "name": prop("string", "Optional token label"),
                    "ttl_seconds": prop("integer", "Token TTL in seconds (default: 3600)")
                ],
                required: ["machine_id"]
            ),
            tool(
                "instabox_machine_diagnostics",
                "Fetch combined CPU/memory metrics, disk filesystems, top processes, and console logs tail for a sandbox.",
                properties: [
                    "machine_id": prop("string", "Target sandbox ID"),
                    "tail": prop("integer", "Number of console log lines to include (default: 120)")
                ],
                required: ["machine_id"]
            ),
            tool(
                "instabox_clipboard_sync",
                "Push text into or pull text from a sandbox's X11/Wayland desktop clipboard.",
                properties: [
                    "machine_id": prop("string", "Target sandbox ID"),
                    "direction": prop("string", "Sync direction", enumValues: ["push", "pull"]),
                    "text": prop("string", "UTF-8 text to write when direction=push")
                ],
                required: ["machine_id", "direction"]
            )
        ]
    }

    // MARK: - Helpers

    private func requireString(_ dict: [String: Any], _ key: String) throws -> String {
        guard let val = dict[key] as? String, !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InstaBoxError.networkError("缺少必填字符串参数：\(key)")
        }
        return val
    }

    private func jsonRPCResult(id: Any, result: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func jsonRPCError(id: Any, code: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": code,
                "message": message
            ]
        ]
    }

    private func encodeJSON(_ obj: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    }

    private func prettyEncode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func toJSONObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func prettyJSONObject(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    private func recordActivity(
        transport: String,
        method: String,
        detail: String,
        started: Date,
        isError: Bool,
        preview: String
    ) async {
        guard let activityHandler else { return }
        let ms = max(0, Int(Date().timeIntervalSince(started) * 1000))
        await activityHandler(
            MCPLogEntry(
                transport: transport,
                method: method,
                detail: detail,
                durationMs: ms,
                isError: isError,
                responsePreview: preview
            )
        )
    }
}
