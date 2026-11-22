import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var bindableStore = store

        ZStack(alignment: .top) {
            if !store.isConnected {
                APILoginView(isAddingAdditional: false)
                    .transition(.opacity)
            } else {
                NavigationSplitView {
                    sidebarContent
                        .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 270)
                } detail: {
                    detailContent
                        .id(store.selectedSection)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.99)),
                                    removal: .opacity
                                )
                        )
                        .animation(reduceMotion ? nil : LiquidMotion.fluid, value: store.selectedSection)
                        .background { GlassBackdrop() }
                }
                .transition(.opacity)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            store.showCreateMachineSheet = true
                        } label: {
                            Label("新建沙盒", systemImage: "plus")
                        }
                        .buttonStyle(.glassProminent)
                        .help("新建 InstaBox 沙盒实例 (⌘N)")
                    }

                    ToolbarSpacer(.fixed, placement: .primaryAction)

                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await store.refreshAll() }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
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

    private var sidebarContent: some View {
        @Bindable var bindableStore = store

        return List(selection: $bindableStore.selectedSection) {
            if let profile = store.activeProfile {
                Section("当前工作区") {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 9) {
                            GlassIconOrb(
                                systemImage: "cube.transparent.fill",
                                tint: .accentColor,
                                size: 32,
                                iconSize: 14,
                                cornerRadius: 10
                            )
                            Text(profile.name)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if let tier = store.currentOrg?.tier ?? profile.tier {
                                TierBadge(tier: tier)
                            }
                        }
                        HStack(spacing: 6) {
                            Text(profile.keyPrefix)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            if let login = store.me?.login ?? profile.userLogin {
                                Text("· @\(login)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("资源管理") {
                NavigationLink(value: SidebarSection.overview) {
                    Label(SidebarSection.overview.title, systemImage: SidebarSection.overview.icon)
                }

                NavigationLink(value: SidebarSection.machines) {
                    HStack {
                        Label(SidebarSection.machines.title, systemImage: SidebarSection.machines.icon)
                        Spacer()
                        if !store.machines.isEmpty {
                            Text("\(store.runningMachineCount)/\(store.machines.count)")
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .contentTransition(.numericText())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .foregroundStyle(store.runningMachineCount > 0 ? Color.green : .secondary)
                                .glassPill(tint: store.runningMachineCount > 0 ? .green.opacity(0.18) : nil)
                                .animation(LiquidMotion.snappy, value: store.runningMachineCount)
                        }
                    }
                }

                NavigationLink(value: SidebarSection.snapshots) {
                    HStack {
                        Label(SidebarSection.snapshots.title, systemImage: SidebarSection.snapshots.icon)
                        Spacer()
                        if !store.snapshots.isEmpty {
                            Text("\(store.snapshots.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                NavigationLink(value: SidebarSection.ports) {
                    HStack {
                        Label(SidebarSection.ports.title, systemImage: SidebarSection.ports.icon)
                        Spacer()
                        if !store.allPorts.isEmpty {
                            Text("\(store.allPorts.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                NavigationLink(value: SidebarSection.secretsAndWebhooks) {
                    Label(SidebarSection.secretsAndWebhooks.title, systemImage: SidebarSection.secretsAndWebhooks.icon)
                }
            }

            Section("API 账户") {
                if store.profiles.count > 1 {
                    ForEach(store.profiles) { p in
                        Button {
                            store.switchProfile(p)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: p.id == store.activeProfileID ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(p.id == store.activeProfileID ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(p.keyPrefix)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                NavigationLink(value: SidebarSection.addAccount) {
                    Label(SidebarSection.addAccount.title, systemImage: SidebarSection.addAccount.icon)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            GlassEffectContainer {
                HStack(spacing: 6) {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在同步云端状态…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let last = store.lastRefreshedAt {
                            Text("更新于 \(last.formatted(date: .omitted, time: .standard))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("尚未刷新")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassPill()
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
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
            color = .green
        case .info:
            icon = "info.circle.fill"
            color = .blue
        case .error:
            icon = "exclamationmark.triangle.fill"
            color = .red
        }

        return GlassEffectContainer {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.body.weight(.semibold))
                    .symbolEffect(.bounce, value: toast.id)
                Text(toast.message)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(3)
                Button {
                    store.toast = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭通知")
                .accessibilityLabel("关闭通知")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassPill(tint: color.opacity(0.20), interactive: true)
            .glassEffectTransition(.materialize)
            .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        }
    }
}
