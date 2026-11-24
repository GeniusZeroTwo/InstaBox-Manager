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
            try verifyTypographyContrastWCAG()
            try verifyBillingQuotaMetrics()
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

    private static func verifyTypographyContrastWCAG() throws {
        // Test against worst-case MeshGradient edge luminance as well as base backdrop
        let lightCard = LiquidPalette.cardScrimLight.composited(over: LiquidPalette.backdropLightEdge)
        let darkCard = LiquidPalette.cardScrimDark.composited(over: LiquidPalette.backdropDarkEdge)
        let lightCardHC = LiquidPalette.cardScrimLightHC.composited(over: LiquidPalette.backdropLightEdge)
        let darkCardHC = LiquidPalette.cardScrimDarkHC.composited(over: LiquidPalette.backdropDarkEdge)
        let lightWell = LiquidPalette.wellFillLight.composited(over: lightCard)
        let darkWell = LiquidPalette.wellFillDark.composited(over: darkCard)
        let lightCode = LiquidPalette.codeCanvasLight.composited(over: lightCard)
        let darkCode = LiquidPalette.codeCanvasDark.composited(over: darkCard)

        // Primary text >= 10:1 (exceeds WCAG AAA 7:1) across all surfaces in both themes
        for (name, fg, bg) in [
            ("light primary/card", LiquidPalette.textPrimaryLight, lightCard),
            ("light primary/well", LiquidPalette.textPrimaryLight, lightWell),
            ("light primary/code", LiquidPalette.textPrimaryLight, lightCode),
            ("dark primary/card", LiquidPalette.textPrimaryDark, darkCard),
            ("dark primary/well", LiquidPalette.textPrimaryDark, darkWell),
            ("dark primary/code", LiquidPalette.textPrimaryDark, darkCode)
        ] {
            let ratio = fg.contrastRatio(against: bg)
            try expect(ratio >= 10.0, "Contrast failed for \(name): \(String(format: "%.2f", ratio)):1 < 10.0:1")
        }

        // Secondary text >= 7.0:1 (WCAG AAA)
        for (name, fg, bg) in [
            ("light secondary/card", LiquidPalette.textSecondaryLight, lightCard),
            ("light secondary/well", LiquidPalette.textSecondaryLight, lightWell),
            ("dark secondary/card", LiquidPalette.textSecondaryDark, darkCard),
            ("dark secondary/well", LiquidPalette.textSecondaryDark, darkWell)
        ] {
            let ratio = fg.contrastRatio(against: bg)
            try expect(ratio >= 7.0, "Contrast failed for \(name): \(String(format: "%.2f", ratio)):1 < 7.0:1")
        }

        // Muted metadata text >= 5.0:1 (exceeds WCAG AA 4.5:1), and >= 7.0:1 in Increased Contrast mode
        for (name, fg, bg) in [
            ("light muted/card", LiquidPalette.textMutedLight, lightCard),
            ("light muted/well", LiquidPalette.textMutedLight, lightWell),
            ("dark muted/card", LiquidPalette.textMutedDark, darkCard),
            ("dark muted/well", LiquidPalette.textMutedDark, darkWell)
        ] {
            let ratio = fg.contrastRatio(against: bg)
            try expect(ratio >= 5.0, "Contrast failed for \(name): \(String(format: "%.2f", ratio)):1 < 5.0:1")
        }
        for (name, fg, bg) in [
            ("light HC muted/card", LiquidPalette.textSecondaryLight, lightCardHC),
            ("dark HC muted/card", LiquidPalette.textSecondaryDark, darkCardHC)
        ] {
            let ratio = fg.contrastRatio(against: bg)
            try expect(ratio >= 7.0, "High-contrast failed for \(name): \(String(format: "%.2f", ratio)):1 < 7.0:1")
        }

        // Segmented picker & electric emerald solid controls: obsidian ink on electric emerald >= 9.0:1
        let emeraldOnContrast = LiquidPalette.onBrandEmerald.contrastRatio(against: LiquidPalette.brandEmeraldSolid)
        try expect(emeraldOnContrast >= 9.0, "On-emerald contrast failed: \(String(format: "%.2f", emeraldOnContrast)):1 < 9.0:1")

        let lightSegActive = LiquidPalette.segmentActiveLight.composited(over: lightWell)
        let darkSegActive = LiquidPalette.segmentActiveDark.composited(over: darkWell)
        for (name, fg, bg) in [
            ("light segment active", LiquidPalette.onBrandEmerald, lightSegActive),
            ("dark segment active", LiquidPalette.onBrandEmerald, darkSegActive)
        ] {
            let ratio = fg.contrastRatio(against: bg)
            try expect(ratio >= 9.0, "Segmented picker contrast failed for \(name): \(String(format: "%.2f", ratio)):1 < 9.0:1")
        }

        // Active selected macOS List row text over accent blue highlight >= 4.5:1
        for (name, fg) in [
            ("selected row primary", LiquidPalette.selectedRowPrimary),
            ("selected row secondary", LiquidPalette.selectedRowSecondary),
            ("selected row muted", LiquidPalette.selectedRowMuted)
        ] {
            let ratio = fg.contrastRatio(against: LiquidPalette.selectionAccentRef)
            try expect(ratio >= 4.5, "Selected list row contrast failed for \(name): \(String(format: "%.2f", ratio)):1 < 4.5:1")
        }

        // Prominent filled buttons: white text >= 4.5:1 across all semantic prominent tints
        let white = LiquidRGB(1.0, 1.0, 1.0, 1.0)
        for (name, bg) in [
            ("prominent green", LiquidPalette.prominentGreen),
            ("prominent blue", LiquidPalette.prominentBlue),
            ("prominent indigo", LiquidPalette.prominentIndigo),
            ("prominent orange", LiquidPalette.prominentOrange)
        ] {
            let ratio = white.contrastRatio(against: bg)
            try expect(ratio >= 4.5, "Prominent button contrast failed for \(name): \(String(format: "%.2f", ratio)):1 < 4.5:1")
        }

        // Semantic status colors >= 4.5:1 (WCAG AA) on card, tinted pill, and tinted well in Light & Dark modes
        let lightStatuses: [(String, LiquidRGB)] = [
            ("green", LiquidPalette.statusGreenLight),
            ("blue", LiquidPalette.statusBlueLight),
            ("orange", LiquidPalette.statusOrangeLight),
            ("red", LiquidPalette.statusRedLight),
            ("purple", LiquidPalette.statusPurpleLight),
            ("indigo", LiquidPalette.statusIndigoLight),
            ("teal", LiquidPalette.statusTealLight),
            ("pink", LiquidPalette.statusPinkLight),
            ("neutral", LiquidPalette.statusNeutralLight)
        ]
        let lightPillBase = LiquidPalette.pillBaseLight.composited(over: lightCard)
        for (label, fg) in lightStatuses {
            let cardRatio = fg.contrastRatio(against: lightCard)
            let tintedPill = fg.withAlpha(0.10).composited(over: lightPillBase)
            let pillRatio = fg.contrastRatio(against: tintedPill)
            let tintedWell = fg.withAlpha(0.09).composited(over: lightWell)
            let wellMutedRatio = LiquidPalette.textMutedLight.contrastRatio(against: tintedWell)
            try expect(cardRatio >= 4.5, "Light status \(label)/card contrast \(String(format: "%.2f", cardRatio)):1 < 4.5:1")
            try expect(pillRatio >= 4.5, "Light status \(label)/pill contrast \(String(format: "%.2f", pillRatio)):1 < 4.5:1")
            try expect(wellMutedRatio >= 4.5, "Light muted text on \(label) well contrast \(String(format: "%.2f", wellMutedRatio)):1 < 4.5:1")
        }

        let darkStatuses: [(String, LiquidRGB)] = [
            ("green", LiquidPalette.statusGreenDark),
            ("blue", LiquidPalette.statusBlueDark),
            ("orange", LiquidPalette.statusOrangeDark),
            ("red", LiquidPalette.statusRedDark),
            ("purple", LiquidPalette.statusPurpleDark),
            ("indigo", LiquidPalette.statusIndigoDark),
            ("teal", LiquidPalette.statusTealDark),
            ("pink", LiquidPalette.statusPinkDark),
            ("neutral", LiquidPalette.statusNeutralDark)
        ]
        let darkPillBase = LiquidPalette.pillBaseDark.composited(over: darkCard)
        for (label, fg) in darkStatuses {
            let cardRatio = fg.contrastRatio(against: darkCard)
            let tintedPill = fg.withAlpha(0.16).composited(over: darkPillBase)
            let pillRatio = fg.contrastRatio(against: tintedPill)
            let tintedWell = fg.withAlpha(0.14).composited(over: darkWell)
            let wellMutedRatio = LiquidPalette.textMutedDark.contrastRatio(against: tintedWell)
            try expect(cardRatio >= 4.5, "Dark status \(label)/card contrast \(String(format: "%.2f", cardRatio)):1 < 4.5:1")
            try expect(pillRatio >= 4.5, "Dark status \(label)/pill contrast \(String(format: "%.2f", pillRatio)):1 < 4.5:1")
            try expect(wellMutedRatio >= 4.5, "Dark muted text on \(label) well contrast \(String(format: "%.2f", wellMutedRatio)):1 < 4.5:1")
        }

        print("  [OK] WCAG 2.1 typography, HC, selected-row, button & pill contrast audit (Light + Dark)")
    }

    private static func verifyBillingQuotaMetrics() throws {
        // 1. Nil / zero free tier
        let empty = BillingQuotaMetrics.compute(usageCost: nil, orgLimits: nil)
        try expect(empty.primaryValueText == "$0.00" && empty.suffixValueText == nil, "Expected $0.00 for nil usage")
        try expect(empty.badgeText == "免费", "Expected 免费 badge, got \(empty.badgeText)")
        try expect(empty.progress == 0.0 && !empty.hasBudgetCap && !empty.isOverBudget, "Expected zero progress & no cap")

        // 2. Uncapped pay-as-you-go must NOT trigger a false 100% red progress bar
        let paygUsage = try JSONDecoder().decode(OrgUsage.self, from: #"{"costUSD": 0.45, "overageUSD": 0.0}"#.data(using: .utf8)!)
        let payg = BillingQuotaMetrics.compute(usageCost: paygUsage, orgLimits: nil)
        try expect(payg.primaryValueText == "$0.45" && payg.suffixValueText == nil, "Unexpected PAYG valueText: \(payg.valueText)")
        try expect(payg.badgeText == "按量", "Unexpected PAYG badge: \(payg.badgeText)")
        try expect(payg.progress == 0.0 && !payg.isOverBudget && !payg.hasBudgetCap, "PAYG without cap must keep calm progress 0")

        // 3. Credits partially spent (creditRemainingUSD + creditsUsedUSD) must reconstruct full period pool
        let spentCreditJSON = #"{"costUSD": 6.00, "creditRemainingUSD": 4.00, "creditsUsedUSD": 6.00, "overageUSD": 0.0}"#.data(using: .utf8)!
        let spentCredit = BillingQuotaMetrics.compute(
            usageCost: try JSONDecoder().decode(OrgUsage.self, from: spentCreditJSON),
            orgLimits: nil
        )
        try expect(spentCredit.valueText == "$6.00 / $10.00", "Expected $6.00 / $10.00, got \(spentCredit.valueText)")
        try expect(spentCredit.badgeText == "60%", "Expected 60% badge, got \(spentCredit.badgeText)")
        try expect(abs(spentCredit.progress - 0.60) < 0.001 && !spentCredit.isOverBudget, "Spent credits must not false-alarm over budget")

        // 4. Plan allowanceUSD + orgLimits.monthlyCreditUSD must NOT double-count
        let proLimits = try JSONDecoder().decode(OrgLimits.self, from: #"{"monthlyCreditUSD": 10.0}"#.data(using: .utf8)!)
        let proUsage = try JSONDecoder().decode(
            OrgUsage.self,
            from: #"{"costUSD": 6.00, "allowanceUSD": 10.00, "creditRemainingUSD": 4.00, "creditsUsedUSD": 6.00, "overageUSD": 0.0}"#.data(using: .utf8)!
        )
        let pro = BillingQuotaMetrics.compute(usageCost: proUsage, orgLimits: proLimits)
        try expect(pro.valueText == "$6.00 / $10.00", "allowanceUSD + monthlyCreditUSD must not double-count; got \(pro.valueText)")
        try expect(pro.badgeText == "60%", "Unexpected pro badge: \(pro.badgeText)")

        // 5. Additive allowance + separate wallet credits
        let pooledJSON = #"{"costUSD": 2.50, "allowanceUSD": 5.00, "creditsUSD": 5.00, "overageUSD": 0.0}"#.data(using: .utf8)!
        let pooled = BillingQuotaMetrics.compute(
            usageCost: try JSONDecoder().decode(OrgUsage.self, from: pooledJSON),
            orgLimits: nil
        )
        try expect(pooled.valueText == "$2.50 / $10.00", "Unexpected pooled valueText: \(pooled.valueText)")
        try expect(pooled.badgeText == "25%", "Unexpected pooled badgeText: \(pooled.badgeText)")

        // 6. Spend cap override
        let capLimits = try JSONDecoder().decode(OrgLimits.self, from: #"{"spendCapUSD": 50.0, "monthlyCreditUSD": 10.0}"#.data(using: .utf8)!)
        let capUsage = try JSONDecoder().decode(OrgUsage.self, from: #"{"costUSD": 25.0, "creditsUSD": 10.0}"#.data(using: .utf8)!)
        let capped = BillingQuotaMetrics.compute(usageCost: capUsage, orgLimits: capLimits)
        try expect(capped.valueText == "$25.00 / $50.00", "Unexpected capped valueText: \(capped.valueText)")
        try expect(capped.badgeText == "50%", "Unexpected capped badgeText: \(capped.badgeText)")

        // 7. Overage alert state (concise badge that never truncates card title)
        let overUsage = try JSONDecoder().decode(
            OrgUsage.self,
            from: #"{"costUSD": 12.0, "allowanceUSD": 5.0, "creditsUSD": 0.0, "overageUSD": 7.0}"#.data(using: .utf8)!
        )
        let over = BillingQuotaMetrics.compute(usageCost: overUsage, orgLimits: nil)
        try expect(over.isOverBudget, "Expected overage flag")
        try expect(over.badgeText == "超额", "Unexpected overage badgeText: \(over.badgeText)")
        try expect(over.subtitleText.contains("$7.00"), "Expected exact overage in subtitle: \(over.subtitleText)")
        try expect(over.progress == 1.0, "Expected clamped progress 1.0 for overage")

        // 8. Negative defensive clamping
        let negUsage = try JSONDecoder().decode(OrgUsage.self, from: #"{"costUSD": -3.0, "creditsUSD": -1.0}"#.data(using: .utf8)!)
        let clamped = BillingQuotaMetrics.compute(usageCost: negUsage, orgLimits: nil)
        try expect(clamped.costUSD == 0 && clamped.creditsUSD == 0 && clamped.progress == 0, "Expected negative values clamped to 0")

        print("  [OK] BillingQuotaMetrics edge-case, credit-pool & unification logic")
    }
}
