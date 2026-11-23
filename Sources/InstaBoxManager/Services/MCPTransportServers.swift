import Foundation
import Network

// MARK: - Stdio MCP Server Runner (`InstaBoxManager --mcp`)

public enum MCPStdioRunner {
    /// Launches a headless MCP JSON-RPC 2.0 server over stdin/stdout and exits cleanly on EOF.
    /// Does NOT initialize AppKit UI or show a Dock icon.
    public static func runAndExit() -> Never {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            await runLoop()
            semaphore.signal()
        }
        semaphore.wait()
        Foundation.exit(0)
    }

    private static func runLoop() async {
        let engine = MCPServerEngine()
        let stdinHandle = FileHandle.standardInput
        let stdoutHandle = FileHandle.standardOutput

        var buffer = Data()
        let newlineByte = UInt8(ascii: "\n")

        while true {
            let chunk: Data
            do {
                guard let readData = try stdinHandle.read(upToCount: 65536), !readData.isEmpty else {
                    break
                }
                chunk = readData
            } catch {
                break
            }
            buffer.append(chunk)

            // Process all complete frames in buffer (supports both standard NDJSON and Content-Length framing)
            while true {
                if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)),
                   let headerStr = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8),
                   headerStr.lowercased().contains("content-length:") {
                    var contentLength = 0
                    for line in headerStr.components(separatedBy: "\r\n") {
                        let lower = line.lowercased()
                        if lower.hasPrefix("content-length:") {
                            contentLength = Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces)) ?? 0
                        }
                    }
                    let bodyStart = headerEnd.upperBound
                    let neededEnd = bodyStart + contentLength
                    guard contentLength > 0, buffer.count >= neededEnd else {
                        break // Wait for remaining bytes
                    }
                    let payload = Data(buffer[bodyStart..<neededEnd])
                    buffer.removeSubrange(buffer.startIndex..<neededEnd)

                    if let respData = await engine.handleRawJSON(payload, transport: "Stdio") {
                        var out = Data("Content-Length: \(respData.count)\r\n\r\n".utf8)
                        out.append(respData)
                        try? stdoutHandle.write(contentsOf: out)
                    }
                    continue
                }

                guard let nlIdx = buffer.firstIndex(of: newlineByte) else {
                    break
                }
                let lineData = Data(buffer[buffer.startIndex..<nlIdx])
                buffer.removeSubrange(buffer.startIndex...nlIdx)

                let trimmed = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if trimmed.isEmpty { continue }

                if let payload = trimmed.data(using: .utf8),
                   let respData = await engine.handleRawJSON(payload, transport: "Stdio") {
                    var out = respData
                    out.append(newlineByte)
                    try? stdoutHandle.write(contentsOf: out)
                }
            }
        }
    }
}

// MARK: - Local Loopback Streamable HTTP MCP Server (`127.0.0.1:<port>/mcp`)

public final class MCPHTTPServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "sh.instabox.mcp.http", qos: .userInitiated)
    private var listener: NWListener?
    private let engine: MCPServerEngine

    public private(set) var port: UInt16 = 28765
    public private(set) var isRunning = false

    public init(engine: MCPServerEngine) {
        self.engine = engine
    }

    public func start(port: UInt16, onStateChange: (@Sendable (Bool, String?) -> Void)? = nil) throws {
        stop()

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: port) ?? 28765
        )

        let newListener = try NWListener(using: params)
        self.port = port
        self.listener = newListener

        newListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
                onStateChange?(true, nil)
            case .failed(let error):
                self?.isRunning = false
                onStateChange?(false, "本地 HTTP MCP 启动失败：\(error.localizedDescription)")
            case .cancelled:
                self?.isRunning = false
                onStateChange?(false, nil)
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }

        newListener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(on: connection, accumulated: Data())
    }

    private func receiveHTTPRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let content {
                buffer.append(content)
            }

            if let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer[..<headerRange.lowerBound]
                let headerText = String(data: headerData, encoding: .utf8) ?? ""
                let bodyStart = headerRange.upperBound

                var contentLength = 0
                for line in headerText.components(separatedBy: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        contentLength = Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces)) ?? 0
                    }
                }

                if buffer.count - bodyStart >= contentLength {
                    let bodyData = Data(buffer[bodyStart..<(bodyStart + contentLength)])
                    self.dispatchHTTP(headerText: headerText, body: bodyData, connection: connection)
                    return
                }
            }

            if isComplete || buffer.count > 16 * 1024 * 1024 {
                connection.cancel()
                return
            }

            self.receiveHTTPRequest(on: connection, accumulated: buffer)
        }
    }

    private func dispatchHTTP(headerText: String, body: Data, connection: NWConnection) {
        let requestLine = headerText.components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]).uppercased() : "GET"
        let rawPath = parts.count > 1 ? String(parts[1]) : "/"
        let path = rawPath.split(separator: "?").first.map(String.init) ?? "/"

        if method == "OPTIONS" {
            sendResponse(connection: connection, status: "204 No Content", contentType: nil, body: Data())
            return
        }

        if method == "GET", (path == "/health" || path == "/" || path == "/mcp") {
            let info: [String: Any] = [
                "status": "ok",
                "server": MCPServerEngine.serverName,
                "version": MCPServerEngine.serverVersion,
                "protocol": MCPServerEngine.defaultProtocolVersion,
                "endpoint": "http://127.0.0.1:\(port)/mcp",
                "tools": MCPServerEngine.toolCatalog.count
            ]
            let data = (try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
            sendResponse(connection: connection, status: "200 OK", contentType: "application/json; charset=utf-8", body: data)
            return
        }

        if method == "POST", (path == "/mcp" || path == "/") {
            let engine = self.engine
            Task {
                if let respData = await engine.handleRawJSON(body, transport: "HTTP") {
                    self.sendResponse(
                        connection: connection,
                        status: "200 OK",
                        contentType: "application/json; charset=utf-8",
                        body: respData
                    )
                } else {
                    self.sendResponse(connection: connection, status: "202 Accepted", contentType: nil, body: Data())
                }
            }
            return
        }

        let errData = Data("{\"error\":\"Not Found\"}".utf8)
        sendResponse(connection: connection, status: "404 Not Found", contentType: "application/json; charset=utf-8", body: errData)
    }

    private func sendResponse(connection: NWConnection, status: String, contentType: String?, body: Data) {
        var headers = [
            "HTTP/1.1 \(status)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "MCP-Protocol-Version: \(MCPServerEngine.defaultProtocolVersion)",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type, Accept, Mcp-Session-Id, MCP-Protocol-Version"
        ]
        if let contentType {
            headers.append("Content-Type: \(contentType)")
        }
        var payload = Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        payload.append(body)

        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
