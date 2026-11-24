import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var sidebarNavNamespace
    @ViewState private var hoveredSection: SidebarSection? = nil

    private let resourceSections: [SidebarSection] = [
        .overview, .machines, .snapshots, .ports, .secretsAndWebhooks, .mcpServer
    ]

    var body: some View {
        @Bindable var bindableStore = store

        ZStack(alignment: .top) {
            if !store.isConnected {
                APILoginView(isAddingAdditional: false)
                    .transition(.opacity)
            } else {
                NavigationSplitView {
                    sidebarContent
                        .navigationSplitViewColumnWidth(min: 224, ideal: 244, max: 276)
                } detail: {
                    detailContent
                        .id(store.selectedSection)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.992)),
                                    removal: .opacity
                                )
                        )
                        .animation(reduceMotion ? nil : LiquidMotion.fluid, value: store.selectedSection)
                        .background { GlassBackdrop() }
                }
                .transition(.opacity)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 6) {
                            LivePulseDot(
                                color: store.runningMachineCount > 0 ? LiquidPalette.statusGreen : LiquidPalette.statusNeutral,
                                isPulsing: store.runningMachineCount > 0,
                                size: 7
                            )
                            Text("运行中")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(LiquidPalette.textMuted)
                            Text("\(store.runningMachineCount)/\(store.machines.count)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(LiquidPalette.statusGreen)
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassPill(tint: store.runningMachineCount > 0 ? LiquidPalette.statusGreen : nil)
                    }

                    ToolbarSpacer(.fixed, placement: .primaryAction)

                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            store.showCreateMachineSheet = true
                        } label: {
                            Label("新建沙盒", systemImage: "plus")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.emeraldPrimary)
                        .help("新建 InstaBox 沙盒实例 (⌘N)")
                    }

                    ToolbarSpacer(.fixed, placement: .primaryAction)

                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await store.refreshAll() }
                        } label: {
                            Label("刷新数据", systemImage: "arrow.clockwise")
                                .symbolEffect(.rotate, isActive: store.isRefreshing && !reduceMotion)
                        }
                        .buttonStyle(.glass)
                        .help("刷新全部状态 (⌘R)")
                    }
                }
                .sheet(isPresented: $bindableStore.showCreateMachineSheet) {
                    CreateMachineSheet()
                        .environment(store)
                }
            }

            if let toast = store.toast {
                toastBanner(toast)
                    .padding(.top, 12)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.92)))
                    .zIndex(99)
            }
        }
        .animation(reduceMotion ? nil : LiquidMotion.fluid, value: store.isConnected)
        .animation(reduceMotion ? nil : LiquidMotion.bouncy, value: store.toast?.id)
    }

    // MARK: - Obsidian-Emerald Custom Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Brand & Workspace Header
                    if let profile = store.activeProfile {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [LiquidPalette.brandEmeraldBright.color, LiquidPalette.brandEmeraldDeep.color],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 34, height: 34)
                                    Image(systemName: "cube.transparent.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(LiquidPalette.onBrandEmerald.color)
                                }
                                .shadow(color: LiquidPalette.brandEmeraldSolid.color.opacity(0.32), radius: 8, y: 2)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(profile.name)
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(LiquidPalette.textPrimary)
                                            .lineLimit(1)
                                        if let tier = store.currentOrg?.tier ?? profile.tier {
                                            TierBadge(tier: tier)
                                        }
                                    }
                                    HStack(spacing: 5) {
                                        if let login = store.me?.login ?? profile.userLogin {
                                            Text("@\(login)")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(LiquidPalette.statusGreen)
                                        }
                                        Text(profile.keyPrefix)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(LiquidPalette.textMuted)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(12)
                        .glassWell(cornerRadius: 14, tint: LiquidPalette.statusGreen)
                    }

                    // Primary Navigation
                    VStack(alignment: .leading, spacing: 5) {
                        Text("NAVIGATION")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(LiquidPalette.textMuted)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 2)

                        ForEach(resourceSections) { section in
                            sidebarNavRow(section)
                        }
                    }

                    // API Workspaces Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("WORKSPACES")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(LiquidPalette.textMuted)
                            .padding(.horizontal, 10)

                        if store.profiles.count > 1 {
                            ForEach(store.profiles) { p in
                                let isActive = p.id == store.activeProfileID
                                Button {
                                    store.switchProfile(p)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                            .font(.caption)
                                            .foregroundStyle(isActive ? LiquidPalette.statusGreen : LiquidPalette.textMuted)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(p.name)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(LiquidPalette.textPrimary)
                                                .lineLimit(1)
                                            Text(p.keyPrefix)
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(LiquidPalette.textMuted)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .liquidWellInteractive(cornerRadius: 10, tint: isActive ? LiquidPalette.statusGreen : nil)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        sidebarNavRow(.addAccount)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            // Bottom Utility Dock (Appearance Switcher + Sync Status — matching reference bottom-left)
            VStack(spacing: 8) {
                Button {
                    withAnimation(reduceMotion ? nil : LiquidMotion.snappy) {
                        store.toggleQuickAppearance()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: colorScheme == .dark ? "sun.max.fill" : "moon.stars.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(colorScheme == .dark ? LiquidPalette.statusOrange : LiquidPalette.statusPurple)
                        Text(colorScheme == .dark ? "明亮模式" : "暗黑翠绿")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LiquidPalette.textPrimary)
                        Spacer()
                        Text(colorScheme == .dark ? "LIGHT" : "DARK")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidPalette.textMuted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .liquidWellInteractive(cornerRadius: 10)
                }
                .buttonStyle(.plain)
                .help("一键切换明亮 / 暗黑翠绿主题")

                HStack(spacing: 6) {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在同步云端状态…")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(LiquidPalette.statusGreen)
                    } else {
                        LivePulseDot(color: LiquidPalette.statusGreen, isPulsing: true, size: 6)
                        if let last = store.lastRefreshedAt {
                            Text("更新于 \(last.formatted(date: .omitted, time: .standard))")
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .foregroundStyle(LiquidPalette.textMuted)
                        } else {
                            Text("就绪")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(LiquidPalette.textMuted)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassWell(cornerRadius: 10)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .padding(.top, 6)
        }
        .background {
            (colorScheme == .dark ? LiquidPalette.sidebarDark.color : LiquidPalette.sidebarLight.color)
                .ignoresSafeArea()
        }
    }

    private func sidebarNavRow(_ section: SidebarSection) -> some View {
        let isSelected = store.selectedSection == section
        let isHovered = hoveredSection == section && !isSelected

        return Button {
            if reduceMotion {
                store.selectedSection = section
            } else {
                withAnimation(LiquidMotion.snappy) {
                    store.selectedSection = section
                }
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 13.5, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? LiquidPalette.onBrandEmerald.color : navIconTint(for: section))
                    .frame(width: 18, alignment: .center)

                Text(section.title)
                    .font(.subheadline.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? LiquidPalette.onBrandEmerald.color : LiquidPalette.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                trailingIndicator(for: section, isSelected: isSelected)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [LiquidPalette.brandEmeraldBright.color, LiquidPalette.brandEmeraldSolid.color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.75)
                        }
                        .shadow(color: LiquidPalette.brandEmeraldSolid.color.opacity(0.32), radius: 10, y: 3)
                        .matchedGeometryEffect(id: "sidebarActivePill", in: sidebarNavNamespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LiquidPalette.statusGreen.opacity(colorScheme == .dark ? 0.12 : 0.08))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredSection = hovering ? section : (hoveredSection == section ? nil : hoveredSection)
        }
    }

    private func navIconTint(for section: SidebarSection) -> Color {
        switch section {
        case .overview: return LiquidPalette.statusGreen
        case .machines: return LiquidPalette.statusBlue
        case .snapshots: return LiquidPalette.statusPurple
        case .ports: return LiquidPalette.statusTeal
        case .secretsAndWebhooks: return LiquidPalette.statusOrange
        case .mcpServer: return LiquidPalette.statusPink
        case .addAccount: return LiquidPalette.textSecondary
        }
    }

    @ViewBuilder
    private func trailingIndicator(for section: SidebarSection, isSelected: Bool) -> some View {
        switch section {
        case .machines where !store.machines.isEmpty:
            Text("\(store.runningMachineCount)/\(store.machines.count)")
                .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2)
                .foregroundStyle(isSelected ? LiquidPalette.onBrandEmerald.color : LiquidPalette.statusGreen)
                .background(
                    (isSelected ? Color.black.opacity(0.14) : LiquidPalette.statusGreen.opacity(0.16)),
                    in: Capsule()
                )
        case .snapshots where !store.snapshots.isEmpty:
            Text("\(store.snapshots.count)")
                .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit())
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2)
                .foregroundStyle(isSelected ? LiquidPalette.onBrandEmerald.color : LiquidPalette.statusPurple)
                .background(
                    (isSelected ? Color.black.opacity(0.14) : LiquidPalette.statusPurple.opacity(0.16)),
                    in: Capsule()
                )
        case .ports where !store.allPorts.isEmpty:
            Text("\(store.allPorts.count)")
                .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit())
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2)
                .foregroundStyle(isSelected ? LiquidPalette.onBrandEmerald.color : LiquidPalette.statusTeal)
                .background(
                    (isSelected ? Color.black.opacity(0.14) : LiquidPalette.statusTeal.opacity(0.16)),
                    in: Capsule()
                )
        case .mcpServer where store.mcpServerRunning:
            HStack(spacing: 4) {
                Circle()
                    .fill(isSelected ? LiquidPalette.onBrandEmerald.color : LiquidPalette.statusGreen)
                    .frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(isSelected ? LiquidPalette.onBrandEmerald.color : LiquidPalette.statusGreen)
            }
        default:
            Text(section.codeTag)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(isSelected ? LiquidPalette.onBrandEmerald.color.opacity(0.75) : LiquidPalette.textMuted.opacity(0.75))
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch store.selectedSection {
        case .overview:
            OverviewDashboardView()
        case .machines:
            MachinesView()
        case .snapshots:
            SnapshotsView()
        case .ports:
            PortsOverviewView()
        case .secretsAndWebhooks:
            SecretsAndWebhooksView()
        case .mcpServer:
            MCPServerView()
        case .addAccount:
            APILoginView(isAddingAdditional: true)
        }
    }

    private func toastBanner(_ toast: BannerToast) -> some View {
        let icon: String
        let color: Color
        switch toast.kind {
        case .success:
            icon = "checkmark.circle.fill"
            color = LiquidPalette.statusGreen
        case .info:
            icon = "info.circle.fill"
            color = LiquidPalette.statusBlue
        case .error:
            icon = "exclamationmark.triangle.fill"
            color = LiquidPalette.statusRed
        }

        return GlassEffectContainer {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.body.weight(.semibold))
                    .symbolEffect(.bounce, value: toast.id)
                Text(toast.message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiquidPalette.textPrimary)
                    .lineLimit(3)
                Button {
                    store.toast = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LiquidPalette.textSecondary)
                }
                .buttonStyle(.plain)
                .help("关闭通知")
                .accessibilityLabel("关闭通知")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassPill(tint: color, interactive: true)
            .glassEffectTransition(.materialize)
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        }
    }
}
