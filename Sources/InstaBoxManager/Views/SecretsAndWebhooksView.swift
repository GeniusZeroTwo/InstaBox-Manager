import SwiftUI

struct SecretsAndWebhooksView: View {
    @Environment(AppStore.self) private var store

    // Secret Form
    @ViewState private var secretName: String = ""
    @ViewState private var secretValue: String = ""
    @ViewState private var secretDelivery: String = "proxy"
    @ViewState private var secretHostsText: String = "*"

    // Webhook Form
    @ViewState private var webhookURL: String = ""
    @ViewState private var webhookDesc: String = ""
    @ViewState private var selectedEventsText: String = "machine.ready,machine.suspended,machine.stopped,machine.deleted"

    @ViewState private var isSubmitting = false

    private var orgId: String? {
        store.currentOrg?.id ?? store.me?.org?.id ?? store.usage?.org?.id
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 20) {
                VStack(alignment: .leading, spacing: 22) {
                    secretsSection
                    webhooksSection
                }
                .padding(24)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .navigationTitle("密钥与 Webhook")
    }

    // MARK: - Org Secrets

    private var secretsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 10) {
                    GlassIconOrb(systemImage: "lock.rectangle.stack", tint: .indigo, size: 32, iconSize: 15, cornerRadius: 10)
                    Text("组织级机密凭据 (Org Secrets)")
                        .font(.title3.bold())
                }
                Spacer()
                Text("仅存储密文摘要，永不回显明文")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .glassPill()
            }

            HStack(spacing: 10) {
                TextField("名称 (如 OPENAI_API_KEY)", text: $secretName)
                    .textFieldStyle(.plain)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .glassWell(cornerRadius: 9)
                    .frame(width: 195)

                SecureField("密钥明文值…", text: $secretValue)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .glassWell(cornerRadius: 9)
                    .frame(minWidth: 180)

                Picker("注入方式", selection: $secretDelivery) {
                    Text("HTTPS 代理注入 (proxy)").tag("proxy")
                    Text("环境变量注入 (env)").tag("env")
                }
                .frame(width: 210)

                if secretDelivery == "proxy" {
                    TextField("允许域名 (逗号分隔或 *)", text: $secretHostsText)
                        .textFieldStyle(.plain)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .glassWell(cornerRadius: 9)
                        .frame(width: 165)
                }

                Button("保存密钥") {
                    saveSecret()
                }
                .buttonStyle(.glassProminent)
                .disabled(secretName.isEmpty || secretValue.isEmpty || orgId == nil || isSubmitting)
            }

            if store.secrets.isEmpty {
                Text("当前工作区暂无已配置的 Org Secret（注意：免费版需付费套餐或开启 orgSecrets 权限方可使用）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(store.secrets) { sec in
                    HStack(spacing: 10) {
                        Text(sec.name)
                            .font(.subheadline.monospaced().bold())
                        Text(sec.delivery)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .glassPill(tint: .indigo.opacity(0.18))
                        if !sec.hosts.isEmpty {
                            Text("Hosts: \(sec.hosts.joined(separator: ", "))")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("v\(sec.version) · \(sec.size)B")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            deleteSecret(sec.name)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                    .padding(11)
                    .glassWell(cornerRadius: 11)
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 20)
    }

    // MARK: - Org Webhooks

    private var webhooksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                GlassIconOrb(systemImage: "antenna.radiowaves.left.and.right", tint: .teal, size: 32, iconSize: 15, cornerRadius: 10)
                Text("生命周期事件 Webhook")
                    .font(.title3.bold())
            }

            HStack(spacing: 10) {
                TextField("https://example.com/webhooks/instabox", text: $webhookURL)
                    .textFieldStyle(.plain)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .glassWell(cornerRadius: 9)

                TextField("备注说明（可选）", text: $webhookDesc)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .glassWell(cornerRadius: 9)
                    .frame(width: 170)

                Button("添加 Webhook") {
                    createWebhook()
                }
                .buttonStyle(.glassProminent)
                .disabled(webhookURL.isEmpty || orgId == nil || isSubmitting)
            }

            HStack(spacing: 8) {
                Text("订阅事件（逗号分隔）：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("事件列表", text: $selectedEventsText)
                    .textFieldStyle(.plain)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassWell(cornerRadius: 8)
            }

            if store.webhooks.isEmpty {
                Text("当前工作区未注册任何 Webhook 回调端点。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(store.webhooks) { wh in
                    HStack(spacing: 10) {
                        LivePulseDot(color: wh.enabled ? .green : .secondary, isPulsing: wh.enabled, size: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(wh.url)
                                .font(.caption.monospaced().bold())
                            Text("事件：\(wh.events.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("发送测试") {
                            testWebhook(wh.id)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)

                        Button(role: .destructive) {
                            deleteWebhook(wh.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                    .padding(11)
                    .liquidWellInteractive(cornerRadius: 11)
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 20)
    }

    // MARK: - Actions

    private func saveSecret() {
        guard let client = store.client, let orgId else { return }
        isSubmitting = true
        let hosts: [String]? = secretDelivery == "proxy"
            ? secretHostsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            : nil
        Task {
            defer { isSubmitting = false }
            do {
                _ = try await client.putOrgSecret(
                    orgId: orgId,
                    name: secretName.trimmingCharacters(in: .whitespacesAndNewlines),
                    request: PutSecretRequest(delivery: secretDelivery, hosts: hosts, value: secretValue)
                )
                secretName = ""
                secretValue = ""
                store.showToast(.success, "密钥已安全写入")
                await store.refreshAll(silent: true)
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }

    private func deleteSecret(_ name: String) {
        guard let client = store.client, let orgId else { return }
        Task {
            do {
                try await client.deleteOrgSecret(orgId: orgId, name: name)
                store.showToast(.info, "已删除密钥 \(name)")
                await store.refreshAll(silent: true)
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }

    private func createWebhook() {
        guard let client = store.client, let orgId else { return }
        isSubmitting = true
        let evs = selectedEventsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        Task {
            defer { isSubmitting = false }
            do {
                let wh = try await client.createOrgWebhook(
                    orgId: orgId,
                    request: CreateWebhookRequest(
                        url: webhookURL.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: webhookDesc.isEmpty ? nil : webhookDesc,
                        events: evs.isEmpty ? ["machine.ready"] : evs
                    )
                )
                webhookURL = ""
                webhookDesc = ""
                if let sec = wh.secret {
                    TerminalLauncher.copyToClipboard(sec)
                    store.showToast(.success, "Webhook 已创建，签名密钥已复制到剪贴板")
                } else {
                    store.showToast(.success, "Webhook 已创建")
                }
                await store.refreshAll(silent: true)
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }

    private func testWebhook(_ id: String) {
        guard let client = store.client, let orgId else { return }
        Task {
            do {
                try await client.testOrgWebhook(orgId: orgId, webhookId: id)
                store.showToast(.success, "已向 Webhook 端点投递测试事件")
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }

    private func deleteWebhook(_ id: String) {
        guard let client = store.client, let orgId else { return }
        Task {
            do {
                try await client.deleteOrgWebhook(orgId: orgId, webhookId: id)
                store.showToast(.info, "已删除 Webhook")
                await store.refreshAll(silent: true)
            } catch {
                store.showToast(.error, error.localizedDescription)
            }
        }
    }
}
