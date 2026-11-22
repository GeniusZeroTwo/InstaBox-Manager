import AppKit
import SwiftUI

struct APILoginView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isAddingAdditional: Bool

    @ViewState private var apiKey: String = ""
    @ViewState private var customName: String = ""
    @ViewState private var baseURL: String = "https://api.instabox.sh"
    @ViewState private var showKeyPlain = false
    @ViewState private var showAdvanced = false
    @ViewState private var isHoveringHero = false
    @ViewState private var heroFloat = false

    private var envKey: String? {
        if let v = ProcessInfo.processInfo.environment["INSTABOX_API_KEY"], !v.isEmpty {
            return v
        }
        return nil
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 22) {
                VStack(spacing: 26) {
                    // Refractive Liquid Glass Hero Emblem
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.accentColor.opacity(0.75),
                                            Color.indigo.opacity(0.65),
                                            Color.cyan.opacity(0.55)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 82, height: 82)
                                .glassCard(cornerRadius: 24, tint: .accentColor.opacity(0.28), interactive: true)

                            Image(systemName: "cube.transparent.fill")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .white.opacity(isHoveringHero ? 0.65 : 0.35), radius: isHoveringHero ? 12 : 8)
                                .symbolEffect(.bounce, value: isHoveringHero)
                        }
                        .scaleEffect(isHoveringHero && !reduceMotion ? 1.07 : 1.0)
                        .offset(y: (!reduceMotion && heroFloat) ? -4 : 0)
                        .shadow(color: Color.accentColor.opacity(isHoveringHero ? 0.34 : 0.14), radius: isHoveringHero ? 24 : 14, y: 8)
                        .onHover { hovering in
                            withAnimation(reduceMotion ? nil : LiquidMotion.bouncy) {
                                isHoveringHero = hovering
                            }
                        }
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                                heroFloat = true
                            }
                        }

                        Text(isAddingAdditional ? "添加工作区" : "InstaBox 管理面板")
                            .font(.system(size: 27, weight: .semibold, design: .rounded))

                        Text(isAddingAdditional ? "连接另一个工作区，随时在侧边栏无缝切换。" : "输入 API Key，在原生液态玻璃工作台中管理你的全部云端沙盒。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, isAddingAdditional ? 10 : 28)
                    .liquidAppear(delay: 0.0)

                    // Input Card
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            HStack(spacing: 9) {
                                GlassIconOrb(systemImage: "key.fill", tint: .accentColor, size: 30, iconSize: 13, cornerRadius: 9)
                                Text("连接 InstaBox API")
                                    .font(.headline)
                            }
                            Spacer()
                            Link(destination: URL(string: "https://dashboard.instabox.sh/dashboard/api-keys")!) {
                                Label("获取 API Key", systemImage: "arrow.up.right.square")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .glassPill(tint: .accentColor.opacity(0.14), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Key")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Group {
                                    if showKeyPlain {
                                        TextField("ibk_...", text: $apiKey)
                                    } else {
                                        SecureField("粘贴以 ibk_ 开头的 API Key…", text: $apiKey)
                                    }
                                }
                                .textFieldStyle(.plain)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .glassWell(cornerRadius: 10)
                                .onSubmit {
                                    connect()
                                }

                                Button {
                                    showKeyPlain.toggle()
                                } label: {
                                    Image(systemName: showKeyPlain ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.glass)
                                .help(showKeyPlain ? "隐藏 API Key" : "显示 API Key")
                                .accessibilityLabel(showKeyPlain ? "隐藏 API Key" : "显示 API Key")

                                Button("粘贴") {
                                    if let str = NSPasteboard.general.string(forType: .string) {
                                        apiKey = str.trimmingCharacters(in: .whitespacesAndNewlines)
                                    }
                                }
                                .buttonStyle(.glass)
                            }

                            if let envKey, apiKey.isEmpty {
                                Button {
                                    apiKey = envKey
                                } label: {
                                    Label("检测到环境变量 INSTABOX_API_KEY（\(KeychainService.maskKey(envKey))），点击一键填入", systemImage: "sparkles")
                                        .font(.caption)
                                }
                                .buttonStyle(.link)
                            }
                        }

                        DisclosureGroup("高级选项（自定义备注名 / API 地址）", isExpanded: $showAdvanced) {
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("工作区备注名称（可选，留空自动读取组织名）")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("例如：个人工作区 / 生产团队", text: $customName)
                                        .textFieldStyle(.plain)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .glassWell(cornerRadius: 9)
                                }

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("API Base URL")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("https://api.instabox.sh", text: $baseURL)
                                        .textFieldStyle(.plain)
                                        .font(.system(.body, design: .monospaced))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .glassWell(cornerRadius: 9)
                                }
                            }
                            .padding(.top, 10)
                        }
                        .font(.caption.weight(.medium))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showAdvanced)

                        if let err = store.authError {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .foregroundStyle(.red)
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassWell(cornerRadius: 10, tint: .red)
                        }

                        HStack {
                            Label("API Key 安全加密存储于 macOS 钥匙串", systemImage: "lock.shield")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                connect()
                            } label: {
                                HStack(spacing: 6) {
                                    if store.isAuthenticating {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Text(store.isAuthenticating ? "正在验证…" : "立即连接")
                                        .fontWeight(.semibold)
                                }
                                .padding(.horizontal, 14)
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isAuthenticating)
                        }
                    }
                    .padding(26)
                    .frame(maxWidth: 560)
                    .glassCard(cornerRadius: 24)
                    .liquidAppear(delay: 0.06)

                    // Saved profiles list when managing multiple API keys
                    if !store.profiles.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("已保存的工作区")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(store.profiles) { profile in
                                let isActive = profile.id == store.activeProfileID
                                HStack(spacing: 12) {
                                    GlassIconOrb(
                                        systemImage: isActive ? "checkmark.seal.fill" : "key.horizontal",
                                        tint: isActive ? .green : .secondary,
                                        size: 36,
                                        iconSize: 15,
                                        cornerRadius: 11
                                    )

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(profile.name)
                                                .font(.body.weight(.medium))
                                            if let tier = profile.tier {
                                                TierBadge(tier: tier)
                                            }
                                            if isActive {
                                                Text("当前使用")
                                                    .font(.caption2.weight(.semibold))
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 2)
                                                    .foregroundStyle(.green)
                                                    .glassPill(tint: .green.opacity(0.20))
                                            }
                                        }
                                        Text("\(profile.keyPrefix) · \(profile.normalizedBaseURL)")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if !isActive {
                                        Button("切换") {
                                            store.switchProfile(profile)
                                        }
                                        .buttonStyle(.glass)
                                    }

                                    Button(role: .destructive) {
                                        store.removeProfile(profile)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)
                                    .help("从钥匙串移除此 API Key")
                                    .accessibilityLabel("移除工作区 \(profile.name)")
                                }
                                .padding(14)
                                .glassCard(
                                    cornerRadius: 16,
                                    tint: isActive ? .green.opacity(0.06) : nil,
                                    interactive: true
                                )
                                .liquidHoverLift(scale: 1.01, liftY: -1.5, glowColor: isActive ? .green : .accentColor)
                            }
                        }
                        .frame(maxWidth: 560)
                        .liquidAppear(delay: 0.12)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .background {
            if !isAddingAdditional {
                GlassBackdrop()
            }
        }
    }

    private func connect() {
        Task {
            let ok = await store.connectWithAPIKey(rawKey: apiKey, customName: customName, baseURL: baseURL)
            if ok {
                apiKey = ""
                customName = ""
            }
        }
    }
}
