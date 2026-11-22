import Foundation

public enum PatchMachineOutcome: Sendable {
    case updated(MachineItem)
    case operation(OperationItem)
}

public struct InstaBoxClient: Sendable {
    public let baseURL: String
    public let apiKey: String
    private let session: URLSession

    public init(baseURL: String = "https://api.instabox.sh", apiKey: String, session: URLSession = .shared) {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if trimmed.hasSuffix("/v1") {
            trimmed = String(trimmed.dropLast(3))
        }
        self.baseURL = trimmed.isEmpty ? "https://api.instabox.sh" : trimmed
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    // MARK: - Core Request Builder & Executor

    public func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        guard var components = URLComponents(string: baseURL + normalizedPath) else {
            throw InstaBoxError.invalidURL(baseURL + normalizedPath)
        }
        let nonEmpty = queryItems.filter { $0.value != nil }
        if !nonEmpty.isEmpty {
            components.queryItems = nonEmpty
        }
        guard let url = components.url else {
            throw InstaBoxError.invalidURL(baseURL + normalizedPath)
        }
        return url
    }

    private func buildRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        idempotent: Bool = false,
        bodyData: Data? = nil,
        contentType: String? = "application/json",
        timeout: TimeInterval = 45
    ) throws -> URLRequest {
        guard !apiKey.isEmpty else {
            throw InstaBoxError.missingAPIKey
        }
        let url = try makeURL(path: path, queryItems: queryItems)
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("InstaBoxManager-macOS-arm64/1.0", forHTTPHeaderField: "User-Agent")

        if idempotent {
            req.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "Idempotency-Key")
        }
        if let bodyData {
            req.httpBody = bodyData
            if let contentType {
                req.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }
        return req
    }

    private func performRaw(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw InstaBoxError.networkError(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw InstaBoxError.invalidResponse
        }
        if !(200...299).contains(http.statusCode) {
            let errDetail = try? JSONDecoder().decode(APIErrorBody.self, from: data).error
            throw InstaBoxError.httpError(statusCode: http.statusCode, detail: errDetail)
        }
        return (data, http)
    }

    private func requestJSON<T: Decodable>(
        _ type: T.Type,
        method: String = "GET",
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        idempotent: Bool = false,
        body: (any Encodable)? = nil,
        timeout: TimeInterval = 45
    ) async throws -> T {
        let bodyData: Data?
        if let body {
            bodyData = try JSONEncoder().encode(AnyEncodable(body))
        } else {
            bodyData = nil
        }
        let req = try buildRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            headers: headers,
            idempotent: idempotent,
            bodyData: bodyData,
            timeout: timeout
        )
        let (data, _) = try await performRaw(req)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw InstaBoxError.decodingError("\(T.self): \(error.localizedDescription)")
        }
    }

    private func requestNoContent(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        idempotent: Bool = false,
        body: (any Encodable)? = nil
    ) async throws {
        let bodyData = try body.map { try JSONEncoder().encode(AnyEncodable($0)) }
        let req = try buildRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            headers: headers,
            idempotent: idempotent,
            bodyData: bodyData
        )
        _ = try await performRaw(req)
    }

    // MARK: - Account, Workspace & Usage

    public func fetchMe() async throws -> MeResponse {
        try await requestJSON(MeResponse.self, path: "/v1/me")
    }

    public func fetchOrgs() async throws -> [OrgItem] {
        let list = try await requestJSON(OrgListResponse.self, path: "/v1/orgs")
        return list.orgs
    }

    public func fetchUsage(orgId: String? = nil) async throws -> UsageResponse {
        var q: [URLQueryItem] = []
        if let orgId, !orgId.isEmpty {
            q.append(URLQueryItem(name: "org", value: orgId))
        }
        return try await requestJSON(UsageResponse.self, path: "/v1/usage", queryItems: q)
    }

    public func fetchMachineUsage(orgId: String? = nil, limit: Int = 50) async throws -> OrgMachineUsageList {
        var q = [URLQueryItem(name: "limit", value: String(limit))]
        if let orgId, !orgId.isEmpty {
            q.append(URLQueryItem(name: "org", value: orgId))
        }
        return try await requestJSON(OrgMachineUsageList.self, path: "/v1/usage/machines", queryItems: q)
    }

    public func fetchTemplates() async throws -> [TemplateItem] {
        let res = try await requestJSON(TemplateListResponse.self, path: "/v1/templates")
        return res.templates
    }

    // MARK: - Machines Lifecycle & CRUD

    public func fetchMachines(limit: Int = 100) async throws -> [MachineItem] {
        var all: [MachineItem] = []
        var cursor: String? = nil
        repeat {
            var q = [URLQueryItem(name: "limit", value: String(limit))]
            if let cursor {
                q.append(URLQueryItem(name: "cursor", value: cursor))
            }
            let page = try await requestJSON(MachineListResponse.self, path: "/v1/machines", queryItems: q)
            all.append(contentsOf: page.machines)
            cursor = page.nextCursor
        } while cursor != nil && !cursor!.isEmpty && all.count < 500
        return all
    }

    public func fetchMachine(id: String) async throws -> MachineItem {
        try await requestJSON(MachineItem.self, path: "/v1/machines/\(id)")
    }

    public func createMachine(_ request: CreateMachineRequest) async throws -> OperationItem {
        try await requestJSON(
            OperationItem.self,
            method: "POST",
            path: "/v1/machines",
            idempotent: true,
            body: request
        )
    }

    public func updateMachine(id: String, request: UpdateMachineRequest) async throws -> PatchMachineOutcome {
        let bodyData = try JSONEncoder().encode(request)
        let req = try buildRequest(
            method: "PATCH",
            path: "/v1/machines/\(id)",
            idempotent: true,
            bodyData: bodyData
        )
        let (data, http) = try await performRaw(req)
        if http.statusCode == 202 {
            let op = try JSONDecoder().decode(OperationItem.self, from: data)
            return .operation(op)
        }
        let machine = try JSONDecoder().decode(MachineItem.self, from: data)
        return .updated(machine)
    }

    public func deleteMachine(id: String, confirmValue: String? = nil, now: Bool = false) async throws -> OperationItem {
        var q: [URLQueryItem] = []
        if now {
            q.append(URLQueryItem(name: "now", value: "true"))
        }
        return try await requestJSON(
            OperationItem.self,
            method: "DELETE",
            path: "/v1/machines/\(id)",
            queryItems: q,
            headers: ["X-Confirm-Delete": confirmValue ?? id],
            idempotent: true
        )
    }

    public func startMachine(id: String) async throws -> OperationItem {
        try await requestJSON(
            OperationItem.self,
            method: "POST",
            path: "/v1/machines/\(id)/start",
            idempotent: true,
            body: EmptyObject()
        )
    }

    public func stopMachine(id: String, now: Bool = false) async throws -> OperationItem {
        try await requestJSON(
            OperationItem.self,
            method: "POST",
            path: "/v1/machines/\(id)/stop",
            idempotent: true,
            body: StopMachineRequest(now: now ? true : nil)
        )
    }

    public func suspendMachine(id: String) async throws -> OperationItem {
        try await requestJSON(
            OperationItem.self,
            method: "POST",
            path: "/v1/machines/\(id)/suspend",
            idempotent: true,
            body: EmptyObject()
        )
    }

    public func resumeMachine(id: String) async throws -> OperationItem {
        try await requestJSON(
            OperationItem.self,
            method: "POST",
            path: "/v1/machines/\(id)/resume",
            idempotent: true,
            body: EmptyObject()
        )
    }

    public func wakeMachine(id: String) async throws -> MachineItem {
        try await requestJSON(
            MachineItem.self,
            method: "POST",
            path: "/v1/machines/\(id)/wake",
            body: EmptyObject()
        )
    }

    public func forkMachine(id: String, request: ForkMachineRequest) async throws -> OperationItem {
        try await requestJSON(
            OperationItem.self,
            method: "POST",
            path: "/v1/machines/\(id)/fork",
            idempotent: true,
            body: request
        )
    }

    public func restoreMachine(id: String, request: RestoreMachineRequest) async throws -> OperationItem {
        try await requestJSON(
            OperationItem.self,
            method: "POST",
            path: "/v1/machines/\(id)/restore",
            idempotent: true,
            body: request
        )
    }

    // MARK: - Operations Long Polling

    public func fetchOperation(id: String, waitSeconds: Int = 20) async throws -> OperationItem {
        var q: [URLQueryItem] = []
        if waitSeconds > 0 {
            q.append(URLQueryItem(name: "wait", value: "\(min(waitSeconds, 25))s"))
        }
        return try await requestJSON(
            OperationItem.self,
            path: "/v1/operations/\(id)",
            queryItems: q,
            timeout: TimeInterval(waitSeconds + 15)
        )
    }

    public func waitForOperation(
        id: String,
        maxDuration: TimeInterval = 180,
        onUpdate: (@MainActor @Sendable (OperationItem) -> Void)? = nil
    ) async throws -> OperationItem {
        let deadline = Date().addingTimeInterval(maxDuration)
        while Date() < deadline {
            try Task.checkCancellation()
            let op = try await fetchOperation(id: id, waitSeconds: 20)
            if let onUpdate {
                await onUpdate(op)
            }
            if op.state == "succeeded" {
                return op
            }
            if op.state == "failed" {
                throw InstaBoxError.operationFailed(op)
            }
        }
        return try await fetchOperation(id: id, waitSeconds: 0)
    }

    // MARK: - Command Execution & SSE Streaming

    public func execCommand(machineId: String, request: ExecRequest) async throws -> ExecResult {
        let timeout = TimeInterval((request.timeoutSeconds ?? 60) + 15)
        return try await requestJSON(
            ExecResult.self,
            method: "POST",
            path: "/v1/machines/\(machineId)/exec",
            body: request,
            timeout: timeout
        )
    }

    public func streamExecCommand(
        machineId: String,
        request: ExecRequest,
        onEvent: @Sendable (ExecStreamEvent) async -> Void
    ) async throws {
        let bodyData = try JSONEncoder().encode(request)
        let timeout = TimeInterval((request.timeoutSeconds ?? 120) + 20)
        let req = try buildRequest(
            method: "POST",
            path: "/v1/machines/\(machineId)/exec",
            headers: ["Accept": "text/event-stream"],
            bodyData: bodyData,
            timeout: timeout
        )

        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw InstaBoxError.invalidResponse
        }

        if !(200...299).contains(http.statusCode) {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let detail = try? JSONDecoder().decode(APIErrorBody.self, from: errorData).error
            throw InstaBoxError.httpError(statusCode: http.statusCode, detail: detail)
        }

        var currentEvent = ""
        var dataLines: [String] = []

        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.isEmpty {
                if let parsed = Self.decodeSSEFrame(event: currentEvent, dataLines: dataLines) {
                    await onEvent(parsed)
                }
                currentEvent = ""
                dataLines.removeAll(keepingCapacity: true)
            } else if line.hasPrefix("event:") {
                currentEvent = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                var value = String(line.dropFirst(5))
                if value.hasPrefix(" ") {
                    value.removeFirst()
                }
                dataLines.append(value)
            }
        }

        if !dataLines.isEmpty, let parsed = Self.decodeSSEFrame(event: currentEvent, dataLines: dataLines) {
            await onEvent(parsed)
        }
    }

    public static func decodeSSEFrame(event: String, dataLines: [String]) -> ExecStreamEvent? {
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n")
        guard let data = payload.data(using: .utf8) else { return nil }

        switch event {
        case "stdout":
            if let chunk = try? JSONDecoder().decode(SSEDataChunk.self, from: data) {
                return .stdout(chunk.data)
            }
        case "stderr":
            if let chunk = try? JSONDecoder().decode(SSEDataChunk.self, from: data) {
                return .stderr(chunk.data)
            }
        case "exit":
            if let result = try? JSONDecoder().decode(ExecResult.self, from: data) {
                return .exit(result)
            }
        case "error":
            if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
                return .error(body.error)
            }
            if let detail = try? JSONDecoder().decode(APIErrorDetail.self, from: data) {
                return .error(detail)
            }
        default:
            break
        }
        return nil
    }

    public func fetchExecHistory(machineId: String, limit: Int = 50) async throws -> [ExecHistoryEntry] {
        let res = try await requestJSON(
            ExecHistoryResponse.self,
            path: "/v1/machines/\(machineId)/history",
            queryItems: [URLQueryItem(name: "limit", value: String(limit))]
        )
        return res.commands
    }

    public func fetchExecHistoryDetail(machineId: String, execId: String) async throws -> ExecHistoryEntry {
        try await requestJSON(ExecHistoryEntry.self, path: "/v1/machines/\(machineId)/history/\(execId)")
    }

    // MARK: - Files

    public func fetchFiles(machineId: String, path: String = "/data/home") async throws -> MachineFilesResponse {
        try await requestJSON(
            MachineFilesResponse.self,
            path: "/v1/machines/\(machineId)/files",
            queryItems: [URLQueryItem(name: "path", value: path)]
        )
    }

    public func uploadFile(
        machineId: String,
        remotePath: String,
        data: Data,
        mode: String? = nil,
        parents: Bool = true
    ) async throws -> FileWrittenResponse {
        var q = [
            URLQueryItem(name: "path", value: remotePath),
            URLQueryItem(name: "parents", value: parents ? "true" : "false")
        ]
        if let mode, !mode.isEmpty {
            q.append(URLQueryItem(name: "mode", value: mode))
        }
        let req = try buildRequest(
            method: "PUT",
            path: "/v1/machines/\(machineId)/files",
            queryItems: q,
            bodyData: data,
            contentType: "application/octet-stream",
            timeout: 120
        )
        let (respData, _) = try await performRaw(req)
        return try JSONDecoder().decode(FileWrittenResponse.self, from: respData)
    }

    public func downloadFileContent(machineId: String, remotePath: String) async throws -> Data {
        let req = try buildRequest(
            method: "GET",
            path: "/v1/machines/\(machineId)/files/content",
            queryItems: [URLQueryItem(name: "path", value: remotePath)],
            headers: ["Accept": "application/octet-stream"],
            timeout: 120
        )
        let (data, _) = try await performRaw(req)
        return data
    }

    // MARK: - Ports & SSH

    public func fetchMachinePorts(machineId: String) async throws -> PublicPortListResponse {
        try await requestJSON(PublicPortListResponse.self, path: "/v1/machines/\(machineId)/ports")
    }

    public func fetchAllPorts() async throws -> PublicPortListResponse {
        try await requestJSON(PublicPortListResponse.self, path: "/v1/ports")
    }

    public func publishPort(machineId: String, request: PublishPortRequest) async throws -> PublicPortItem {
        try await requestJSON(
            PublicPortItem.self,
            method: "POST",
            path: "/v1/machines/\(machineId)/ports",
            body: request
        )
    }

    public func unpublishPort(machineId: String, port: Int) async throws {
        try await requestNoContent(method: "DELETE", path: "/v1/machines/\(machineId)/ports/\(port)")
    }

    public func fetchConnectionInfo(machineId: String) async throws -> ConnectionInfoResponse {
        try await requestJSON(ConnectionInfoResponse.self, path: "/v1/machines/\(machineId)/connection-info")
    }

    public func fetchSSHTokens(machineId: String) async throws -> [SSHTokenInfoItem] {
        let res = try await requestJSON(SSHTokenListResponse.self, path: "/v1/machines/\(machineId)/ssh-tokens")
        return res.tokens
    }

    public func createSSHToken(machineId: String, request: CreateSSHTokenRequest) async throws -> SSHTokenResponse {
        try await requestJSON(
            SSHTokenResponse.self,
            method: "POST",
            path: "/v1/machines/\(machineId)/ssh-tokens",
            body: request
        )
    }

    public func revokeSSHToken(machineId: String, tokenId: String) async throws {
        try await requestNoContent(method: "DELETE", path: "/v1/machines/\(machineId)/ssh-tokens/\(tokenId)")
    }

    public func revokeAllSSHTokens(machineId: String) async throws {
        let req = try buildRequest(method: "DELETE", path: "/v1/machines/\(machineId)/ssh-tokens")
        _ = try await performRaw(req)
    }

    // MARK: - Remote Desktop

    public func desktopAction(machineId: String, request: DesktopActionRequest) async throws -> DesktopStatusResponse {
        try await requestJSON(
            DesktopStatusResponse.self,
            method: "POST",
            path: "/v1/machines/\(machineId)/desktop",
            body: request
        )
    }

    public func createDesktopStream(machineId: String, request: DesktopStreamRequest) async throws -> DesktopStreamResponse {
        try await requestJSON(
            DesktopStreamResponse.self,
            method: "POST",
            path: "/v1/machines/\(machineId)/desktop/stream",
            body: request
        )
    }

    public func revokeDesktopStreams(machineId: String) async throws {
        try await requestNoContent(method: "DELETE", path: "/v1/machines/\(machineId)/desktop/stream")
    }

    // MARK: - Metrics, Disk, Processes & Logs

    public func fetchMachineLogs(machineId: String, tail: Int = 300) async throws -> MachineLogsResponse {
        try await requestJSON(
            MachineLogsResponse.self,
            path: "/v1/machines/\(machineId)/logs",
            queryItems: [URLQueryItem(name: "tail", value: String(tail))]
        )
    }

    public func fetchMachineMetrics(machineId: String) async throws -> MachineMetricsResponse {
        try await requestJSON(MachineMetricsResponse.self, path: "/v1/machines/\(machineId)/metrics")
    }

    public func fetchMachineDisk(machineId: String) async throws -> MachineDiskResponse {
        try await requestJSON(MachineDiskResponse.self, path: "/v1/machines/\(machineId)/disk")
    }

    public func fetchMachineProcesses(machineId: String, all: Bool = true) async throws -> ProcessListResponse {
        try await requestJSON(
            ProcessListResponse.self,
            path: "/v1/machines/\(machineId)/processes",
            queryItems: [URLQueryItem(name: "all", value: all ? "true" : "false")]
        )
    }

    // MARK: - Snapshots

    public func fetchSnapshots() async throws -> [SnapshotItem] {
        let res = try await requestJSON(SnapshotListResponse.self, path: "/v1/snapshots")
        return res.snapshots
    }

    public func createSnapshot(machineId: String, request: CreateSnapshotRequest) async throws -> SnapshotItem {
        try await requestJSON(
            SnapshotItem.self,
            method: "POST",
            path: "/v1/machines/\(machineId)/snapshots",
            idempotent: true,
            body: request
        )
    }

    public func deleteSnapshot(id: String, confirmValue: String? = nil) async throws {
        try await requestNoContent(
            method: "DELETE",
            path: "/v1/snapshots/\(id)",
            headers: ["X-Confirm-Delete": confirmValue ?? id],
            idempotent: true
        )
    }

    public func fetchSnapshotFiles(snapshotId: String, path: String = "/") async throws -> MachineFilesResponse {
        try await requestJSON(
            MachineFilesResponse.self,
            path: "/v1/snapshots/\(snapshotId)/files",
            queryItems: [URLQueryItem(name: "path", value: path)]
        )
    }

    // MARK: - Org Secrets & Webhooks

    public func fetchOrgSecrets(orgId: String) async throws -> [OrgSecretItem] {
        let res = try await requestJSON(SecretListResponse.self, path: "/v1/orgs/\(orgId)/secrets")
        return res.items
    }

    public func putOrgSecret(orgId: String, name: String, request: PutSecretRequest) async throws -> OrgSecretItem {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return try await requestJSON(
            OrgSecretItem.self,
            method: "PUT",
            path: "/v1/orgs/\(orgId)/secrets/\(encodedName)",
            body: request
        )
    }

    public func deleteOrgSecret(orgId: String, name: String) async throws {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        try await requestNoContent(method: "DELETE", path: "/v1/orgs/\(orgId)/secrets/\(encodedName)")
    }

    public func fetchOrgWebhooks(orgId: String) async throws -> WebhookListResponse {
        try await requestJSON(WebhookListResponse.self, path: "/v1/orgs/\(orgId)/webhooks")
    }

    public func createOrgWebhook(orgId: String, request: CreateWebhookRequest) async throws -> WebhookItem {
        try await requestJSON(
            WebhookItem.self,
            method: "POST",
            path: "/v1/orgs/\(orgId)/webhooks",
            body: request
        )
    }

    public func deleteOrgWebhook(orgId: String, webhookId: String) async throws {
        try await requestNoContent(method: "DELETE", path: "/v1/orgs/\(orgId)/webhooks/\(webhookId)")
    }

    public func testOrgWebhook(orgId: String, webhookId: String) async throws {
        let req = try buildRequest(method: "POST", path: "/v1/orgs/\(orgId)/webhooks/\(webhookId)/test")
        _ = try await performRaw(req)
    }
}

private struct EmptyObject: Encodable {}

private struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) {
        self.encodeImpl = wrapped.encode(to:)
    }
    func encode(to encoder: Encoder) throws {
        try encodeImpl(encoder)
    }
}
