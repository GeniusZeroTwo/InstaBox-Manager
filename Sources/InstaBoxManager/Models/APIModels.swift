import Foundation

// MARK: - Saved API Profile

public struct APIProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var baseURL: String
    public var keyPrefix: String
    public var userLogin: String?
    public var orgId: String?
    public var orgName: String?
    public var tier: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: String = "https://api.instabox.sh",
        keyPrefix: String,
        userLogin: String? = nil,
        orgId: String? = nil,
        orgName: String? = nil,
        tier: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.keyPrefix = keyPrefix
        self.userLogin = userLogin
        self.orgId = orgId
        self.orgName = orgName
        self.tier = tier
        self.createdAt = createdAt
    }

    public var normalizedBaseURL: String {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if trimmed.hasSuffix("/v1") {
            trimmed = String(trimmed.dropLast(3))
        }
        return trimmed.isEmpty ? "https://api.instabox.sh" : trimmed
    }
}

// MARK: - API Errors

public struct APIErrorBody: Codable, Sendable {
    public let error: APIErrorDetail
}

public struct APIErrorDetail: Codable, Sendable, Equatable {
    public let code: String
    public let message: String
    public let requestId: String?
    public let retryable: Bool?
    public let operationId: String?
    public let reason: String?
    public let hint: String?
    public let docs: String?
    public let docsUrl: String?
    public let retryAfterSeconds: Int?
    public let requiredScopes: [String]?

    enum CodingKeys: String, CodingKey {
        case code, message, requestId, retryable, operationId, reason, hint, docs
        case docsUrl = "docs_url"
        case retryAfterSeconds, requiredScopes
    }
}

public enum InstaBoxError: LocalizedError, Sendable {
    case invalidURL(String)
    case missingAPIKey
    case invalidResponse
    case httpError(statusCode: Int, detail: APIErrorDetail?)
    case operationFailed(OperationItem)
    case decodingError(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "无效的 API 地址：\(url)"
        case .missingAPIKey:
            return "尚未配置 API Key，请先输入 InstaBox API Key（ibk_...）。"
        case .invalidResponse:
            return "服务器返回了无法识别的响应。"
        case .httpError(let status, let detail):
            if let detail {
                var text = "[\(status) \(detail.code)] \(Self.friendlyTitle(for: detail.code, fallback: detail.message))"
                if let hint = detail.hint, !hint.isEmpty {
                    text += "\n提示：\(hint)"
                } else if detail.message != Self.friendlyTitle(for: detail.code, fallback: detail.message) {
                    text += "\n详情：\(detail.message)"
                }
                if let scopes = detail.requiredScopes, !scopes.isEmpty {
                    text += "\n所需权限 Scope：\(scopes.joined(separator: ", "))"
                }
                return text
            }
            return "HTTP 请求失败（状态码 \(status)）"
        case .operationFailed(let op):
            if let err = op.error {
                return "操作 \(op.type) 失败：[\(err.code)] \(err.message)"
            }
            return "操作 \(op.type) 失败（ID: \(op.id)）"
        case .decodingError(let msg):
            return "数据解析失败：\(msg)"
        case .networkError(let msg):
            return "网络连接异常：\(msg)"
        }
    }

    public static func friendlyTitle(for code: String, fallback: String) -> String {
        switch code {
        case "missing_key": return "缺少 API Key"
        case "malformed_key": return "API Key 格式不正确（应以 ibk_ 或 iba_ 开头）"
        case "invalid_key": return "API Key 无效或不存在"
        case "expired_key", "api_key_expired": return "API Key 已过期"
        case "revoked_key", "api_key_revoked": return "API Key 已被吊销"
        case "missing_scope", "insufficient_scope": return "当前 API Key 缺少该操作所需的权限范围（Scope）"
        case "permission_denied": return "权限不足（部分账户级接口仅限网页登录会话或管理员调用）"
        case "machine_not_running": return "沙盒当前未运行，请先启动或恢复沙盒"
        case "operation_conflict": return "当前沙盒正在执行另一项操作，或当前状态不支持该变更"
        case "delete_confirmation_required": return "删除确认校验未通过（X-Confirm-Delete）"
        case "spec_not_allowed": return "当前套餐不支持所选的机型配置或磁盘大小"
        case "template_not_allowed": return "当前免费套餐仅支持 agent-browser、android、omarchy、ci 模板或快照"
        case "quota_exceeded": return "已达到套餐配额上限：\(fallback)"
        case "no_capacity": return "当前宿主机资源暂时不足，请稍后重试"
        case "host_unavailable": return "沙盒所在宿主机暂时不可达，请稍后重试"
        case "machine_cooldown": return "沙盒处于最大运行时长冷却期，请稍后再唤醒"
        case "fork_unavailable": return "当前沙盒状态不支持直接 Fork，建议先保存快照"
        default: return fallback
        }
    }
}

// MARK: - Account, Orgs & Usage

public struct MeResponse: Codable, Sendable {
    public let userId: Int
    public let login: String
    public let name: String?
    public let email: String?
    public let avatarUrl: String?
    public let activated: Bool?
    public let admin: Bool?
    public let orgId: String?
    public let org: OrgRef?
    public let workspaces: [OrgRef]?
    public let allowedSpecs: [MachineSpec]?
    public let alwaysOnAllowed: Bool?
    public let diskResize: String?
    public let fixedAutoSuspendSeconds: Int?
    public let idleChoicesSeconds: [Int]?
    public let machineMetrics: Bool?
    public let manualLifecycle: Bool?
    public let resizeRestart: Bool?
    public let webhooksEnabled: Bool?
}

public struct OrgRef: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let tier: String
    public let kind: String
    public let alwaysOnAllowed: Bool?
}

public struct OrgListResponse: Codable, Sendable {
    public let orgs: [OrgItem]
}

public struct OrgItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let personal: Bool
    public let tier: String
    public let role: String?
    public let createdAt: String?
    public let allowedSpecs: [MachineSpec]?
    public let limits: OrgLimits?
    public let usage: OrgUsage?
    public let billing: OrgBilling?
}

public struct OrgLimits: Codable, Hashable, Sendable {
    public let alwaysOn: Bool?
    public let freeSandboxHours: Double?
    public let freeSandboxes: Int?
    public let maxDiskGiB: Int?
    public let maxMachines: Int?
    public let maxMembers: Int?
    public let maxRunning: Int?
    public let maxSnapshots: Int?
    public let maxStoredGiB: Int?
    public let maxVCPUs: Int?
    public let monthlyCreditUSD: Double?
    public let spendCapUSD: Double?
    public let startsPerMinute: Int?
}

public struct OrgUsage: Codable, Hashable, Sendable {
    public let allocatedDiskGiB: Int?
    public let allowanceUSD: Double?
    public let billableDiskGiB: Double?
    public let chargedUSD: Double?
    public let costUSD: Double?
    public let creditRemainingUSD: Double?
    public let creditsExpireAt: String?
    public let creditsUSD: Double?
    public let creditsUsedUSD: Double?
    public let egressGiB: Double?
    public let egressUSD: Double?
    public let freeMachines: Int?
    public let freeSandboxHours: Double?
    public let gpuUSD: Double?
    public let machines: Int?
    public let memGiBHours: Double?
    public let memUSD: Double?
    public let overageUSD: Double?
    public let periodStart: String?
    public let periodEnd: String?
    public let ratedUntil: String?
    public let remainingUSD: Double?
    public let running: Int?
    public let runtimeUSD: Double?
    public let snapshots: Int?
    public let storageGiBHours: Double?
    public let storageUSD: Double?
    public let storedBytes: Int64?
    public let vcpuHours: Double?
    public let vcpuUSD: Double?
}

public struct OrgBilling: Codable, Hashable, Sendable {
    public let cancelAtPeriodEnd: Bool?
    public let funding: String?
    public let periodStart: String?
    public let periodEnd: String?
    public let status: String?
    public let subscribed: Bool?
    public let tier: String?
}

public struct UsageResponse: Codable, Sendable {
    public let allocatedDiskGiB: Int?
    public let computedAt: String?
    public let exclusiveBytes: Int64?
    public let logicalBytes: Int64?
    public let storedBytes: Int64?
    public let images: Int?
    public let machines: Int
    public let snapshots: Int
    public let limits: UsageLimits
    public let cost: OrgUsage?
    public let org: OrgRef?
}

public struct UsageLimits: Codable, Sendable {
    public let liveSnapshots: Bool?
    public let machineSpec: MachineSpec?
    public let machineSpecs: [MachineSpec]?
    public let maxImages: Int?
    public let maxMachines: Int
    public let maxSnapshots: Int
    public let maxStoredGiB: Int
    public let orgSecrets: Bool?
    public let unlimited: [String]?
}

public struct OrgMachineUsageList: Codable, Sendable {
    public let from: String
    public let to: String
    public let total: Int
    public let machines: [OrgMachineUsageItem]
}

public struct OrgMachineUsageItem: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let computeUSD: Double
    public let free: Bool
    public let runningSeconds: Int
    public let vcpuSeconds: Int
    public let memGiBSeconds: Double
    public let gpuSeconds: Int?
    public let gpuType: String?
    public let gpuUSD: Double?
    public let deletedAt: String?
}

// MARK: - Templates & Specs

public struct MachineSpec: Codable, Hashable, Sendable {
    public let vcpus: Int
    public let memMiB: Int
    public let persistentDiskGiB: Int?
    public let rootDiskGiB: Int?
    public let gpuType: String?
    public let gpus: Int?

    public var displayLabel: String {
        let gib = Double(memMiB) / 1024.0
        let memText = gib.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(gib)) GiB" : String(format: "%.1f GiB", gib)
        if let gpuType, let gpus, gpus > 0 {
            return "\(vcpus) vCPU · \(memText) · \(gpus)x \(gpuType.uppercased())"
        }
        return "\(vcpus) vCPU · \(memText)"
    }
}

public struct TemplateListResponse: Codable, Sendable {
    public let templates: [TemplateItem]
}

public struct TemplateItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let version: String
    public let arch: String
    public let digest: String
    public let description: String?
    public let creatable: Bool?
    public let `default`: Bool?
    public let hidden: Bool?
    public let restricted: Bool?
    public let gpu: Bool?
    public let os: String?
    public let defaultSpec: MachineSpec
    public let sizes: [MachineSpec]?
}

// MARK: - Machines (Sandboxes)

public enum MachineState: String, Codable, CaseIterable, Sendable {
    case creating
    case starting
    case running
    case stopping
    case stopped
    case suspending
    case suspended
    case resuming
    case deleting
    case deleted
    case error
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MachineState(rawValue: raw) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .creating: return "创建中"
        case .starting: return "启动中"
        case .running: return "运行中"
        case .stopping: return "停止中"
        case .stopped: return "已停止"
        case .suspending: return "暂停中"
        case .suspended: return "已暂停"
        case .resuming: return "恢复中"
        case .deleting: return "删除中"
        case .deleted: return "已删除"
        case .error: return "异常"
        case .unknown: return "未知"
        }
    }

    public var isTransitioning: Bool {
        switch self {
        case .creating, .starting, .stopping, .suspending, .resuming, .deleting:
            return true
        default:
            return false
        }
    }
}

public struct MachineListResponse: Codable, Sendable {
    public let machines: [MachineItem]
    public let nextCursor: String?
}

public struct MachineItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let orgId: String
    public let state: MachineState
    public let desiredState: MachineState?
    public let guestUser: String
    public let spec: MachineSpec
    public let template: TemplateRef
    public let snapshot: SnapshotRef?
    public let storage: StorageInfo?
    public let runtime: RuntimeInfo?
    public let autoSuspendAfterSeconds: Int?
    public let autoSuspendedAt: String?
    public let maxRunMinutes: Int?
    public let metadata: [String: String]?
    public let envNames: [String]?
    public let free: Bool?
    public let suspendable: Bool?
    public let vault: Bool?
    public let oomKills: Int?
    public let lastOom: OOMKillInfo?
    public let lastError: APIErrorDetail?
    public let abuseLock: MachineAbuseLock?
    public let cooldownReason: String?
    public let cooldownUntil: String?
    public let operationId: String?
    public let createdAt: String
    public let updatedAt: String
    public let readyAt: String?
    public let runStartedAt: String?

    public static func == (lhs: MachineItem, rhs: MachineItem) -> Bool {
        lhs.id == rhs.id && lhs.updatedAt == rhs.updatedAt && lhs.state == rhs.state && lhs.name == rhs.name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct TemplateRef: Codable, Hashable, Sendable {
    public let id: String
    public let version: String
    public let digest: String?
    public let kernel: String?
}

public struct SnapshotRef: Codable, Hashable, Sendable {
    public let id: String
}

public struct StorageInfo: Codable, Hashable, Sendable {
    public let sizeGiB: Int
    public let mountPath: String
    public let persistent: Bool
    public let synced: Bool
    public let snapshotSeq: Int64?
}

public struct RuntimeInfo: Codable, Hashable, Sendable {
    public let ready: Bool
    public let hostUnreachable: Bool?
    public let hostLastSeenAt: String?
    public let processesPreserved: Bool?
}

public struct OOMKillInfo: Codable, Hashable, Sendable {
    public let at: String
    public let pid: Int
    public let process: String
    public let rssBytes: Int64
    public let anonRssBytes: Int64
    public let cgroup: Bool
}

public struct MachineAbuseLock: Codable, Hashable, Sendable {
    public let at: String
    public let explanation: String
    public let what: String
    public let appeal: String
}

public struct DiskWarning: Codable, Hashable, Sendable {
    public let mount: String
    public let usedPct: Double
    public let level: String
    public let message: String
    public let noSpace: Bool?
}

// MARK: - Machine Mutations & Operations

public struct CreateMachineRequest: Codable, Sendable {
    public var name: String?
    public var templateId: String?
    public var snapshotId: String?
    public var vcpus: Int?
    public var memMiB: Int?
    public var desiredState: String?
    public var autoSuspendAfterSeconds: Int?
    public var maxRunMinutes: Int?
    public var env: [String: String]?
    public var metadata: [String: String]?

    public init(
        name: String? = nil,
        templateId: String? = nil,
        snapshotId: String? = nil,
        vcpus: Int? = nil,
        memMiB: Int? = nil,
        desiredState: String? = "running",
        autoSuspendAfterSeconds: Int? = nil,
        maxRunMinutes: Int? = nil,
        env: [String: String]? = nil,
        metadata: [String: String]? = nil
    ) {
        self.name = name
        self.templateId = templateId
        self.snapshotId = snapshotId
        self.vcpus = vcpus
        self.memMiB = memMiB
        self.desiredState = desiredState
        self.autoSuspendAfterSeconds = autoSuspendAfterSeconds
        self.maxRunMinutes = maxRunMinutes
        self.env = env
        self.metadata = metadata
    }
}

public struct UpdateMachineRequest: Codable, Sendable {
    public var name: String?
    public var vcpus: Int?
    public var memMiB: Int?
    public var persistentDiskGiB: Int?
    public var autoSuspendAfterSeconds: Int?
    public var maxRunMinutes: Int?
    public var metadata: [String: String]?
    public var apply: String?

    public init(
        name: String? = nil,
        vcpus: Int? = nil,
        memMiB: Int? = nil,
        persistentDiskGiB: Int? = nil,
        autoSuspendAfterSeconds: Int? = nil,
        maxRunMinutes: Int? = nil,
        metadata: [String: String]? = nil,
        apply: String? = nil
    ) {
        self.name = name
        self.vcpus = vcpus
        self.memMiB = memMiB
        self.persistentDiskGiB = persistentDiskGiB
        self.autoSuspendAfterSeconds = autoSuspendAfterSeconds
        self.maxRunMinutes = maxRunMinutes
        self.metadata = metadata
        self.apply = apply
    }
}

public struct ForkMachineRequest: Codable, Sendable {
    public var name: String?
    public var vcpus: Int?
    public var memMiB: Int?
    public var metadata: [String: String]?

    public init(name: String? = nil, vcpus: Int? = nil, memMiB: Int? = nil, metadata: [String: String]? = nil) {
        self.name = name
        self.vcpus = vcpus
        self.memMiB = memMiB
        self.metadata = metadata
    }
}

public struct RestoreMachineRequest: Codable, Sendable {
    public var snapshotId: String
    public var desiredState: String?

    public init(snapshotId: String, desiredState: String? = "running") {
        self.snapshotId = snapshotId
        self.desiredState = desiredState
    }
}

public struct StopMachineRequest: Codable, Sendable {
    public var now: Bool?
    public var timeoutSeconds: Int?
    public init(now: Bool? = nil, timeoutSeconds: Int? = nil) {
        self.now = now
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct OperationItem: Codable, Identifiable, Sendable {
    public let id: String
    public let machineId: String
    public let type: String
    public let state: String // queued, running, succeeded, failed
    public let phase: String?
    public let trigger: String?
    public let createdAt: String
    public let updatedAt: String
    public let error: APIErrorDetail?

    public var isFinished: Bool {
        state == "succeeded" || state == "failed"
    }
}

// MARK: - Exec, Streaming & History

public struct ExecRequest: Codable, Sendable {
    public var cmd: String?
    public var argv: [String]?
    public var cwd: String?
    public var envs: [String: String]?
    public var stdin: String?
    public var timeoutSeconds: Int?
    public var noHistory: Bool?

    public init(
        cmd: String? = nil,
        argv: [String]? = nil,
        cwd: String? = nil,
        envs: [String: String]? = nil,
        stdin: String? = nil,
        timeoutSeconds: Int? = nil,
        noHistory: Bool? = nil
    ) {
        self.cmd = cmd
        self.argv = argv
        self.cwd = cwd
        self.envs = envs
        self.stdin = stdin
        self.timeoutSeconds = timeoutSeconds
        self.noHistory = noHistory
    }
}

public struct ExecResult: Codable, Sendable {
    public let exitCode: Int
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool
    public let truncated: Bool
    public let signal: String?
    public let oomKilled: Bool?
    public let invalidUtf8: Bool?
    public let diskWarning: DiskWarning?
}

public struct SSEDataChunk: Codable, Sendable {
    public let data: String
}

public enum ExecStreamEvent: Sendable {
    case stdout(String)
    case stderr(String)
    case exit(ExecResult)
    case error(APIErrorDetail)
}

public struct ExecHistoryResponse: Codable, Sendable {
    public let commands: [ExecHistoryEntry]
    public let nextCursor: String?
}

public struct ExecHistoryEntry: Codable, Identifiable, Sendable {
    public let id: String
    public let machineId: String
    public let command: String
    public let cwd: String?
    public let exitCode: Int
    public let status: String
    public let durationMs: Int
    public let startedAt: String
    public let endedAt: String
    public let stdoutBytes: Int
    public let stderrBytes: Int
    public let stdout: String?
    public let stderr: String?
    public let timedOut: Bool
    public let truncated: Bool
}

// MARK: - Files

public struct MachineFilesResponse: Codable, Sendable {
    public let path: String
    public let type: String // dir, file, other
    public let mode: String
    public let modTime: String
    public let size: Int64
    public let content: String?
    public let binary: Bool?
    public let truncated: Bool?
    public let entries: [FileEntry]?
}

public struct FileEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: String { name + "_" + type }
    public let name: String
    public let type: String // dir, file, symlink, other
    public let size: Int64
    public let mode: String
    public let modTime: String
    public let target: String?

    public var isDirectory: Bool {
        type == "dir"
    }
}

public struct FileWrittenResponse: Codable, Sendable {
    public let path: String
    public let size: Int64
    public let mode: String
    public let sha256: String
    public let created: Bool
}

// MARK: - Metrics, Disk, Processes & Logs

public struct MachineLogsResponse: Codable, Sendable {
    public let machineId: String
    public let state: String
    public let console: String
    public let cursor: Int64
    public let consoleTruncated: Bool?
    public let consoleUnavailable: String?
    public let operations: [OperationItem]
}

public struct MachineMetricsResponse: Codable, Sendable {
    public let metrics: [MachineMetric]
    public let disk: MachineDiskResponse?
}

public struct MachineMetric: Codable, Identifiable, Sendable {
    public var id: String { timestamp }
    public let timestamp: String
    public let cpuCount: Int
    public let cpuUsedPct: Double
    public let memTotal: Int64
    public let memUsed: Int64
    public let diskTotal: Int64
    public let diskUsed: Int64?
    public let diskReadBytesPerSec: Double?
    public let diskWriteBytesPerSec: Double?
    public let netInBytesPerSec: Double?
    public let netOutBytesPerSec: Double?
    public let gpuCount: Int?
    public let gpuUsedPct: Double?
}

public struct MachineDiskResponse: Codable, Sendable {
    public let measuredAt: String
    public let filesystems: [MachineFilesystem]
    public let warning: DiskWarning?
}

public struct MachineFilesystem: Codable, Identifiable, Sendable {
    public var id: String { mount }
    public let mount: String
    public let sizeBytes: Int64
    public let usedBytes: Int64
    public let availableBytes: Int64
    public let usedPct: Double
    public let inodesUsedPct: Double
    public let level: String
}

public struct ProcessListResponse: Codable, Sendable {
    public let machineId: String
    public let capturedAt: String
    public let live: Bool
    public let state: String
    public let truncated: Bool
    public let processes: [ProcessInfoItem]
}

public struct ProcessInfoItem: Codable, Identifiable, Sendable {
    public var id: Int { pid }
    public let pid: Int
    public let ppid: Int
    public let user: String
    public let cpuPercent: Double
    public let memPercent: Double
    public let elapsedSeconds: Int
    public let command: String
}

// MARK: - Snapshots

public struct SnapshotListResponse: Codable, Sendable {
    public let snapshots: [SnapshotItem]
}

public struct SnapshotItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let orgId: String
    public let status: String // pending, ready, failed
    public let description: String?
    public let sourceMachineId: String
    public let rootSizeBytes: Int64
    public let dataSizeBytes: Int64?
    public let exclusiveBytes: Int64?
    public let sizeLocked: Bool?
    public let guestUser: String?
    public let template: TemplateRef
    public let visibility: String?
    public let error: String?
    public let createdAt: String
}

public struct CreateSnapshotRequest: Codable, Sendable {
    public var name: String
    public var description: String?
    public var rootOnly: Bool?

    public init(name: String, description: String? = nil, rootOnly: Bool? = nil) {
        self.name = name
        self.description = description
        self.rootOnly = rootOnly
    }
}

// MARK: - Ports & SSH

public struct PublicPortListResponse: Codable, Sendable {
    public let enabled: Bool
    public let ports: [PublicPortItem]
}

public struct PublicPortItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let machineId: String
    public let name: String
    public let port: Int
    public let `protocol`: String?
    public let access: String // public, private
    public let url: String
    public let token: String?
    public let tokenUrl: String?
    public let createdAt: String
}

public struct PublishPortRequest: Codable, Sendable {
    public var port: Int
    public var name: String?
    public var access: String?
    public var `protocol`: String?
    public var rotateToken: Bool?

    public init(port: Int, name: String? = nil, access: String? = "public", protocol proto: String? = "http", rotateToken: Bool? = nil) {
        self.port = port
        self.name = name
        self.access = access
        self.`protocol` = proto
        self.rotateToken = rotateToken
    }
}

public struct ConnectionInfoResponse: Codable, Sendable {
    public let machineId: String
    public let host: String
    public let port: Int
    public let username: String
    public let transport: String
    public let capabilities: [String]
    public let moshHost: String?
    public let moshPort: Int?
}

public struct SSHTokenResponse: Codable, Identifiable, Sendable {
    public let id: String
    public let machineId: String
    public let name: String
    public let host: String
    public let port: Int
    public let token: String
    public let command: String
    public let moshCommand: String?
    public let hostKeyFingerprint: String
    public let expiresAt: String?
}

public struct SSHTokenListResponse: Codable, Sendable {
    public let tokens: [SSHTokenInfoItem]
}

public struct SSHTokenInfoItem: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let createdAt: String
    public let expiresAt: String?
    public let revokedAt: String?
    public let command: String?
    public let moshCommand: String?
}

public struct CreateSSHTokenRequest: Codable, Sendable {
    public var name: String?
    public var ttlSeconds: Int?
    public var noExpiry: Bool?

    public init(name: String? = nil, ttlSeconds: Int? = 86400, noExpiry: Bool? = nil) {
        self.name = name
        self.ttlSeconds = ttlSeconds
        self.noExpiry = noExpiry
    }
}

// MARK: - Desktop

public struct DesktopStatusResponse: Codable, Sendable {
    public let installed: Bool
    public let installing: Bool
    public let running: Bool
    public let failed: Bool
    public let agentPausable: Bool
    public let kind: String?
    public let os: String?
    public let controller: String?
    public let hint: String?
    public let controlError: String?
    public let log: String?
}

public struct DesktopActionRequest: Codable, Sendable {
    public var action: String
    public var width: Int?
    public var height: Int?

    public init(action: String, width: Int? = nil, height: Int? = nil) {
        self.action = action
        self.width = width
        self.height = height
    }
}

public struct DesktopStreamRequest: Codable, Sendable {
    public var viewOnly: Bool
    public var ttlSeconds: Int

    public init(viewOnly: Bool = false, ttlSeconds: Int = 3600) {
        self.viewOnly = viewOnly
        self.ttlSeconds = ttlSeconds
    }
}

public struct DesktopStreamResponse: Codable, Sendable {
    public let url: String
    public let expiresAt: String
}

// MARK: - Org Secrets & Webhooks

public struct SecretListResponse: Codable, Sendable {
    public let items: [OrgSecretItem]
}

public struct OrgSecretItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let orgId: String
    public let delivery: String // proxy, env
    public let hosts: [String]
    public let size: Int
    public let version: Int
    public let createdAt: String
    public let updatedAt: String
}

public struct PutSecretRequest: Codable, Sendable {
    public var delivery: String
    public var hosts: [String]?
    public var value: String

    public init(delivery: String, hosts: [String]? = nil, value: String) {
        self.delivery = delivery
        self.hosts = hosts
        self.value = value
    }
}

public struct WebhookListResponse: Codable, Sendable {
    public let items: [WebhookItem]
    public let eventTypes: [String]
    public let maxEndpoints: Int
}

public struct WebhookItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let orgId: String
    public let url: String
    public let description: String
    public let enabled: Bool
    public let events: [String]
    public let secret: String?
    public let failingSince: String?
    public let disabledReason: String?
    public let createdAt: String
    public let updatedAt: String
}

public struct CreateWebhookRequest: Codable, Sendable {
    public var url: String
    public var description: String?
    public var events: [String]
    public var enabled: Bool?

    public init(url: String, description: String? = nil, events: [String], enabled: Bool? = true) {
        self.url = url
        self.description = description
        self.events = events
        self.enabled = enabled
    }
}

// MARK: - Formatting Helpers

public enum Formatters {
    public static func bytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }

    public static func usd(_ value: Double?) -> String {
        guard let value else { return "$0.00" }
        return String(format: "$%.2f", value)
    }

    public static func durationSeconds(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let mins = seconds / 60
        if mins < 60 { return "\(mins)m \(seconds % 60)s" }
        let hours = mins / 60
        if hours < 24 { return "\(hours)h \(mins % 60)m" }
        let days = hours / 24
        return "\(days)d \(hours % 24)h"
    }

    public static func relativeOrShortTime(_ isoString: String?) -> String {
        guard let isoString, !isoString.isEmpty else { return "—" }
        let isoWithFrac = ISO8601DateFormatter()
        isoWithFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        guard let date = isoWithFrac.date(from: isoString) ?? isoPlain.date(from: isoString) else {
            return isoString
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
