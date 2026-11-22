import SwiftUI

struct OverviewDashboardView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                        .liquidAppear(delay: 0.0)
                    quotaGridSection
                        .liquidAppear(delay: 0.05)
                    billingAndRuntimeSection
                        .liquidAppear(delay: 0.10)
                    machineCostTableSection
                        .liquidAppear(delay: 0.15)
                }
                .padding(24)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .navigationTitle("概览与配额")
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 16) {
            GlassIconOrb(systemImage: "sparkles.rectangle.stack.fill", tint: .accentColor, size: 44, iconSize: 20, cornerRadius: 14)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(store.currentOrg?.name ?? store.activeProfile?.name ?? "InstaBox 工作区")
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    if let tier = store.currentOrg?.tier ?? store.usage?.org?.tier {
                        TierBadge(tier: tier)
                    }
                }
                HStack(spacing: 12) {
                    if let me = store.me {
                        Label("@\(me.login)", systemImage: "person.circle")
                    }
                    if let orgId = store.currentOrg?.id ?? store.usage?.org?.id {
                        Label(orgId, systemImage: "building.2")
                            .textSelection(.enabled)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.showCreateMachineSheet = true
            } label: {
                Label("创建新沙盒", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22, tint: .accentColor.opacity(0.05))
    }

    private var quotaGridSection: some View {
        let machineCount = store.usage?.machines ?? store.machines.count
        let maxMachines = store.usage?.limits.maxMachines ?? store.currentOrg?.limits?.maxMachines ?? 1
        let isUnlimitedMachines = store.usage?.limits.unlimited?.contains("maxMachines") == true || maxMachines <= 0

        let snapCount = store.usage?.snapshots ?? store.snapshots.count
        let maxSnaps = store.usage?.limits.maxSnapshots ?? store.currentOrg?.limits?.maxSnapshots ?? 5

        let storedBytes = store.usage?.storedBytes ?? store.currentOrg?.usage?.storedBytes ?? 0
        let maxStoredGiB = store.usage?.limits.maxStoredGiB ?? store.currentOrg?.limits?.maxStoredGiB ?? 200
        let storedGiB = Double(storedBytes) / 1_073_741_824.0

        let costUSD = store.usage?.cost?.costUSD ?? store.currentOrg?.usage?.costUSD ?? 0
        let creditsUSD = store.usage?.cost?.creditsUSD ?? store.currentOrg?.usage?.creditsUSD ?? 0

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
            MetricCard(
                title: "沙盒实例",
                value: isUnlimitedMachines ? "\(machineCount) 台" : "\(machineCount) / \(maxMachines)",
                subtitle: "当前运行中 \(store.runningMachineCount) 台",
                icon: "server.rack",
                tint: .blue,
                progress: isUnlimitedMachines ? nil : Double(machineCount) / Double(max(maxMachines, 1))
            )

            MetricCard(
                title: "快照数量",
                value: "\(snapCount) / \(maxSnaps)",
                subtitle: "支持从快照秒级创建与原地还原",
                icon: "externaldrive.badge.timemachine",
                tint: .purple,
                progress: maxSnaps > 0 ? Double(snapCount) / Double(maxSnaps) : nil
            )

            MetricCard(
                title: "持久化与快照存储",
                value: String(format: "%.2f / %d GiB", storedGiB, maxStoredGiB),
                subtitle: "已分配磁盘 \(store.usage?.allocatedDiskGiB ?? 0) GiB",
                icon: "internaldrive",
                tint: .teal,
                progress: maxStoredGiB > 0 ? storedGiB / Double(maxStoredGiB) : nil
            )

            MetricCard(
                title: "本月账单用量",
                value: Formatters.usd(costUSD),
                subtitle: "账户可用余额 \(Formatters.usd(creditsUSD))",
                icon: "dollarsign.circle",
                tint: .green
            )
        }
    }

    @ViewBuilder
    private var billingAndRuntimeSection: some View {
        if let cost = store.usage?.cost ?? store.currentOrg?.usage {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    GlassIconOrb(systemImage: "chart.bar.xaxis", tint: .indigo, size: 28, iconSize: 13, cornerRadius: 8)
                    Text("本月资源计量明细")
                        .font(.headline)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 12)], spacing: 12) {
                    miniStat("vCPU 时长", String(format: "%.2f vCPU·h (%@)", cost.vcpuHours ?? 0, Formatters.usd(cost.vcpuUSD)))
                    miniStat("内存时长", String(format: "%.2f GiB·h (%@)", cost.memGiBHours ?? 0, Formatters.usd(cost.memUSD)))
                    miniStat("存储计费", String(format: "%.2f GiB·h (%@)", cost.storageGiBHours ?? 0, Formatters.usd(cost.storageUSD)))
                    miniStat("出站流量 (Egress)", String(format: "%.3f GiB (%@)", cost.egressGiB ?? 0, Formatters.usd(cost.egressUSD)))
                    miniStat("套餐赠送额度", Formatters.usd(cost.allowanceUSD))
                    miniStat("超出套餐费用", Formatters.usd(cost.overageUSD))
                }
            }
            .padding(20)
            .glassCard(cornerRadius: 20)
        }
    }

    private func miniStat(_ label: String, _ val: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(val)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidWellInteractive(cornerRadius: 12)
    }

    private var machineCostTableSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    GlassIconOrb(systemImage: "clock.badge.checkmark", tint: .teal, size: 28, iconSize: 13, cornerRadius: 8)
                    Text("沙盒运行时长与费用（含已删除沙盒）")
                        .font(.headline)
                }
                Spacer()
                Text(store.machineUsages.count > 20 ? "显示 20 / \(store.machineUsages.count) 条" : "共 \(store.machineUsages.count) 条记录")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .glassPill()
            }

            if store.machineUsages.isEmpty {
                Text("暂无本月沙盒计费记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(26)
                    .glassWell(cornerRadius: 14)
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Text("沙盒名称 / ID")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("运行时长")
                            .frame(width: 95, alignment: .trailing)
                        Text("vCPU 秒数")
                            .frame(width: 90, alignment: .trailing)
                        Text("计费类型")
                            .frame(width: 76, alignment: .center)
                        Text("计算费用")
                            .frame(width: 86, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

                    ForEach(store.machineUsages.prefix(20)) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(item.name)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    if item.deletedAt != nil {
                                        Text("已删除")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1.5)
                                            .foregroundStyle(.secondary)
                                            .glassPill()
                                    }
                                }
                                Text(item.id)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text(Formatters.durationSeconds(item.runningSeconds))
                                .font(.caption.monospacedDigit())
                                .frame(width: 95, alignment: .trailing)

                            Text("\(item.vcpuSeconds)s")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .trailing)

                            Text(item.free ? "免费额度" : "按量计费")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .foregroundStyle(item.free ? .green : .primary)
                                .glassPill(tint: item.free ? .green.opacity(0.18) : nil)
                                .frame(width: 76, alignment: .center)

                            Text(Formatters.usd(item.computeUSD))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .frame(width: 86, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .glassWell(cornerRadius: 11)
                    }
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 20)
    }
}
