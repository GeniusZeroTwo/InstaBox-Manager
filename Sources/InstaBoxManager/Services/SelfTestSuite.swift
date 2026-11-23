import Foundation

public enum SelfTestSuite {
    public static func runAndExit() -> Never {
        do {
            try verifyArchitecture()
            try verifyURLNormalization()
            try verifyMachineAndUsageDecoding()
            try verifySSEStreamDecoding()
            try verifyErrorLocalization()
            try verifyClipboardJSEscaping()
            try verifyMCPProtocolEngine()
            print("PASS: All InstaBoxManager arm64 self-tests succeeded.")
            Foundation.exit(0)
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw NSError(domain: "InstaBoxSelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func verifyArchitecture() throws {
        #if arch(arm64)
        print("  [OK] Architecture: arm64 (Apple Silicon Native)")
        #else
        throw NSError(domain: "InstaBoxSelfTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Binary must be arm64"])
        #endif
    }

    private static func verifyURLNormalization() throws {
        let p1 = APIProfile(name: "Test", baseURL: "https://api.instabox.sh/v1/", keyPrefix: "ibk_1234")
        try expect(p1.normalizedBaseURL == "https://api.instabox.sh", "Expected normalized baseURL without /v1/")

        let client = InstaBoxClient(baseURL: "https://api.instabox.sh/v1", apiKey: "ibk_testkey")
        let url = try client.makeURL(path: "/v1/machines", queryItems: [URLQueryItem(name: "limit", value: "50")])
        try expect(url.absoluteString == "https://api.instabox.sh/v1/machines?limit=50", "Unexpected URL: \(url)")
        print("  [OK] URL builder & profile normalization")
    }

    private static func verifyMachineAndUsageDecoding() throws {
        let sampleJSON = """
        {
          "machines": [
            {
              "id": "m_2a3b4c5d6e7f2a3b4c5d6e7f2a",
              "name": "agent-box-01",
              "orgId": "org_123",
              "state": "running",
              "desiredState": "running",
              "guestUser": "user",
              "spec": {
                "vcpus": 4,
                "memMiB": 8192,
                "persistentDiskGiB": 20
              },
              "template": {
                "id": "agent-browser",
                "version": "2026-11-01",
                "digest": "sha256:abcdef"
              },
              "storage": {
                "sizeGiB": 20,
                "mountPath": "/data",
                "persistent": true,
                "synced": true
              },
              "runtime": {
                "ready": true
              },
              "autoSuspendAfterSeconds": 1800,
              "maxRunMinutes": 480,
              "metadata": {"env": "dev"},
              "vault": false,
              "operationId": null,
              "createdAt": "2026-11-21T10:00:00Z",
              "updatedAt": "2026-11-21T10:05:00Z"
            }
          ],
          "nextCursor": null
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(MachineListResponse.self, from: sampleJSON)
        try expect(decoded.machines.count == 1, "Expected 1 machine")
        try expect(decoded.machines[0].state == .running, "Expected running state")
        try expect(decoded.machines[0].spec.displayLabel == "4 vCPU · 8 GiB", "Unexpected spec label")
        print("  [OK] OpenAPI v1 MachineList JSON decoding")
    }

    private static func verifySSEStreamDecoding() throws {
        let out = InstaBoxClient.decodeSSEFrame(event: "stdout", dataLines: [#"{"data":"hello\n"}"#])
        if case .stdout(let s) = out {
            try expect(s == "hello\n", "Unexpected stdout payload")
        } else {
            try expect(false, "Expected .stdout event")
        }

        let exitEv = InstaBoxClient.decodeSSEFrame(
            event: "exit",
            dataLines: [#"{"stdout":"","stderr":"","exitCode":0,"timedOut":false,"truncated":false}"#]
        )
        if case .exit(let res) = exitEv {
            try expect(res.exitCode == 0 && !res.timedOut, "Unexpected exit payload")
        } else {
            try expect(false, "Expected .exit event")
        }
        print("  [OK] SSE text/event-stream frame parser")
    }

    private static func verifyErrorLocalization() throws {
        let detail = APIErrorDetail(
            code: "invalid_key",
            message: "no such API key",
            requestId: "req_123",
            retryable: false,
            operationId: nil,
            reason: "invalid_key",
            hint: "create an API key at dashboard.instabox.sh",
            docs: nil,
            docsUrl: nil,
            retryAfterSeconds: nil,
            requiredScopes: nil
        )
        let err = InstaBoxError.httpError(statusCode: 401, detail: detail)
        try expect(err.localizedDescription.contains("API Key 无效或不存在"), "Expected localized Chinese error message")
        print("  [OK] API error code localization")
    }

    private static func verifyClipboardJSEscaping() throws {
        let sample = "Hello \"InstaBox\"\n中文复制\\测试"
        let literal = SandboxClipboardSync.jsStringLiteral(sample)
        try expect(literal.hasPrefix("\"") && literal.hasSuffix("\""), "Expected quoted JS string literal")
        try expect(literal.contains("\\n") && literal.contains("\\\""), "Expected escaped newline and quote")
        print("  [OK] Bidirectional clipboard JS literal escaping")
    }

    private static func verifyMCPProtocolEngine() throws {
        let sem = DispatchSemaphore(value: 0)
        var capturedError: Error?

        Task {
            do {
                let engine = MCPServerEngine(clientProvider: { nil })

                let initResp = await engine.handleRequestObject([
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": ["protocolVersion": "2025-03-26"]
                ])
                try expect(initResp != nil, "Expected initialize response")
                let initRes = initResp?["result"] as? [String: Any]
                try expect((initRes?["protocolVersion"] as? String) == "2025-03-26", "Expected negotiated protocolVersion")

                let notifResp = await engine.handleRequestObject([
                    "jsonrpc": "2.0",
                    "method": "notifications/initialized"
                ])
                try expect(notifResp == nil, "Notifications must not return a JSON-RPC response")

                let toolsResp = await engine.handleRequestObject([
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "tools/list"
                ])
                let toolsResult = toolsResp?["result"] as? [String: Any]
                let toolsList = toolsResult?["tools"] as? [[String: Any]] ?? []
                try expect(toolsList.count == MCPServerEngine.toolCatalog.count && toolsList.count >= 18, "Expected 18 MCP tools")

                let resResp = await engine.handleRequestObject([
                    "jsonrpc": "2.0",
                    "id": 3,
                    "method": "resources/list"
                ])
                let resResult = resResp?["result"] as? [String: Any]
                let resources = resResult?["resources"] as? [[String: Any]] ?? []
                try expect(resources.count == 4, "Expected 4 MCP resources")

                let errResp = await engine.handleRequestObject([
                    "jsonrpc": "2.0",
                    "id": 4,
                    "method": "unknown/method"
                ])
                let errObj = errResp?["error"] as? [String: Any]
                try expect((errObj?["code"] as? Int) == -32601, "Expected -32601 for unknown MCP method")
            } catch {
                capturedError = error
            }
            sem.signal()
        }

        sem.wait()
        if let capturedError {
            throw capturedError
        }
        print("  [OK] Native MCP JSON-RPC 2.0 protocol engine (18 tools, 4 resources)")
    }
}
