import SwiftUI

/// Pure, testable helper that normalizes monthly billing KPI display values and utilization ratio
/// so the "本月账单用量" card matches the exact structure, baseline, and visual language of quota cards.
public struct BillingQuotaMetrics: Equatable, Sendable {
    public let costUSD: Double
    public let creditsUSD: Double
    public let allowanceUSD: Double
    public let overageUSD: Double
    public let budgetUSD: Double
    public let hasBudgetCap: Bool
    public let progress: Double
    public let primaryValueText: String
    public let suffixValueText: String?
    public let valueText: String
    public let badgeText: String
    public let subtitleText: String
    public let isOverBudget: Bool

    public static func compute(usageCost: OrgUsage?, orgLimits: OrgLimits?) -> BillingQuotaMetrics {
        let costUSD = max(0, usageCost?.costUSD ?? 0)
        let allowanceUSD = max(0, usageCost?.allowanceUSD ?? 0)
        let overageUSD = max(0, usageCost?.overageUSD ?? 0)
        let spendCapUSD = max(0, orgLimits?.spendCapUSD ?? 0)
        let monthlyCreditUSD = max(0, orgLimits?.monthlyCreditUSD ?? 0)
        let remainingUSD = max(0, usageCost?.remainingUSD ?? 0)
        let creditsUsedUSD = max(0, usageCost?.creditsUsedUSD ?? 0)
        let creditsRemainingUSD = max(0, usageCost?.creditRemainingUSD ?? usageCost?.creditsUSD ?? 0)

        // Included plan allowance should never double-count allowanceUSD and orgLimits.monthlyCreditUSD.
        let planAllowanceUSD = max(allowanceUSD, monthlyCreditUSD)

        // Reconstruct total period credit pool when creditRemainingUSD / creditsUsedUSD are reported.
        let creditPoolUSD: Double = {
            if usageCost?.creditRemainingUSD != nil {
                if creditsUsedUSD > 0 {
                    return creditsRemainingUSD + creditsUsedUSD
                }
                if planAllowanceUSD == 0 && overageUSD == 0 && costUSD > 0 {
                    return creditsRemainingUSD + costUSD
                }
                return creditsRemainingUSD
            }
            if creditsUsedUSD > 0 {
                return creditsRemainingUSD + creditsUsedUSD
            }
            return creditsRemainingUSD
        }()

        let budgetUSD: Double = {
            if spendCapUSD > 0 { return spendCapUSD }
            if planAllowanceUSD > 0 && creditPoolUSD > 0 {
                // Avoid double-counting when creditRemainingUSD/creditsUsedUSD tracks the same plan allowance.
                let tracksPlanAllowance =
                    (creditsUsedUSD > 0 && abs(creditPoolUSD - planAllowanceUSD) < 0.01 && remainingUSD == 0)
                    || (usageCost?.creditRemainingUSD != nil && creditsUsedUSD == 0 && abs((creditsRemainingUSD + costUSD) - planAllowanceUSD) < 0.01)
                return tracksPlanAllowance ? planAllowanceUSD : (planAllowanceUSD + creditPoolUSD)
            }
            if planAllowanceUSD > 0 { return planAllowanceUSD }
            if creditPoolUSD > 0 { return creditPoolUSD }
            if remainingUSD > 0 { return costUSD + remainingUSD }
            return 0
        }()

        let hasBudgetCap = budgetUSD > 0
        let isOverBudget = overageUSD > 0 || (hasBudgetCap && costUSD > budgetUSD)

        let progress: Double = {
            if overageUSD > 0 { return 1.0 }
            if hasBudgetCap {
                return min(max(costUSD / budgetUSD, 0), 1)
            }
            // Uncapped pay-as-you-go without a budget cap must not render a false 100% red danger bar.
            return 0.0
        }()

        let primaryValueText = Formatters.usd(costUSD)
        let suffixValueText: String? = hasBudgetCap ? "/ \(Formatters.usd(budgetUSD))" : nil
        let valueText: String = {
            if let suffixValueText {
                return "\(primaryValueText) \(suffixValueText)"
            }
            return primaryValueText
        }()

        let badgeText: String = {
            if isOverBudget {
                return "超额"
            }
            if hasBudgetCap {
                return "\(Int(round(progress * 100)))%"
            }
            return costUSD == 0 ? "免费" : "按量"
        }()

        let subtitleText: String = {
            if overageUSD > 0 {
                return "超出 \(Formatters.usd(overageUSD)) · 余额 \(Formatters.usd(creditsRemainingUSD))"
            }
            if allowanceUSD > 0 && creditsRemainingUSD > 0 {
                return "可用余额 \(Formatters.usd(creditsRemainingUSD)) · 赠送 \(Formatters.usd(allowanceUSD))"
            }
            if allowanceUSD > 0 {
                return "套餐赠送额度 \(Formatters.usd(allowanceUSD))"
            }
            return "账户可用余额 \(Formatters.usd(creditsRemainingUSD))"
        }()

        return BillingQuotaMetrics(
            costUSD: costUSD,
            creditsUSD: creditsRemainingUSD,
            allowanceUSD: allowanceUSD,
            overageUSD: overageUSD,
            budgetUSD: budgetUSD,
            hasBudgetCap: hasBudgetCap,
            progress: progress,
            primaryValueText: primaryValueText,
            suffixValueText: suffixValueText,
            valueText: valueText,
            badgeText: badgeText,
            subtitleText: subtitleText,
            isOverBudget: isOverBudget
        )
    }
}

struct OverviewDashboardView: View {
    @Environment(AppStore.self) private var store
    @ViewState private var contentWidth: CGFloat = 960

    private var kpiColumns: [GridItem] {
        // Require >= 920pt detail width for 4-up so all 4 KPI headers & figures stay crisp without truncation.
        // At minimum window width (1080px, ~845pt detail), this renders a clean symmetric 2x2 grid.
        let count = contentWidth >= 920 ? 4 : 2
        return Array(repeating: GridItem(.flexible(minimum: 180), spacing: 14), count: count)
    }

    private var breakdownColumns: [GridItem] {
        let count = contentWidth >= 680 ? 3 : 2
        return Array(repeating: GridItem(.flexible(minimum: 170), spacing: 12), count: count)
    }

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
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            if abs(newWidth - contentWidth) > 4 {
                contentWidth = newWidth
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .navigationTitle("概览与配额")
    }

    private var headerSection: some View {
        let costSource = store.usage?.cost ?? store.currentOrg?.usage
        let credits = costSource?.creditRemainingUSD ?? costSource?.creditsUSD ?? 0

        return HStack(spacing: 14) {
            // Left: Workspace Identity & Live Status Card
            HStack(alignment: .center, spacing: 16) {
                GlassIconOrb(
                    systemImage: "sparkles.rectangle.stack.fill",
                    tint: LiquidPalette.statusGreen,
                    size: 46,
                    iconSize: 20,
                    cornerRadius: 14
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(store.currentOrg?.name ?? store.activeProfile?.name ?? "InstaBox 工作区")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(LiquidPalette.textPrimary)
                            .lineLimit(1)
                        if let tier = store.currentOrg?.tier ?? store.usage?.org?.tier {
                            TierBadge(tier: tier)
                        }
                        Text("正常使用中")
                            .font(.system(size: 10.5, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .solidEmeraldPill()
                    }
                    HStack(spacing: 14) {
                        if let me = store.me {
                            Label("@\(me.login)", systemImage: "person.circle")
                                .foregroundStyle(LiquidPalette.statusGreen)
                        }
                        if let orgId = store.currentOrg?.id ?? store.usage?.org?.id {
                            Label(orgId, systemImage: "building.2")
                                .foregroundStyle(LiquidPalette.textSecondary)
                                .textSelection(.enabled)
                        }
                        Label("可用余额 \(Formatters.usd(credits))", systemImage: "wallet.bifold")
                            .foregroundStyle(LiquidPalette.statusTeal)
                    }
                    .font(.caption.weight(.semibold))
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .glassCard(cornerRadius: 20, tint: LiquidPalette.statusGreen.opacity(0.05), accentTopColor: LiquidPalette.statusGreen)

            // Right: Signature Solid Electric Emerald CTA Tile (echoing reference's emerald hero block)
            Button {
                store.showCreateMachineSheet = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.14))
                            .frame(width: 42, height: 42)
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(LiquidPalette.onBrandEmerald.color)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("快速部署")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(LiquidPalette.onBrandEmerald.color.opacity(0.76))
                        Text("创建新沙盒")
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(LiquidPalette.onBrandEmerald.color)
                        Text("秒级启动云端环境")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(LiquidPalette.onBrandEmerald.color.opacity(0.80))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(minWidth: 210, minHeight: 96, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [LiquidPalette.brandEmeraldBright.color, LiquidPalette.brandEmeraldDeep.color],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: LiquidPalette.brandEmeraldSolid.color.opacity(0.32), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
            .liquidHoverLift(scale: 1.015, liftY: -2, glowColor: LiquidPalette.brandEmeraldSolid.color)
            .help("新建 InstaBox 沙盒实例 (⌘N)")
        }
    }

    private var quotaGridSection: some View {
        let machineCount = store.usage?.machines ?? store.machines.count
        let maxMachines = store.usage?.limits.maxMachines ?? store.currentOrg?.limits?.maxMachines ?? 1
        let isUnlimitedMachines = store.usage?.limits.unlimited?.contains("maxMachines") == true || maxMachines <= 0
        let machineProgress: Double = {
            if isUnlimitedMachines {
                return machineCount > 0 ? Double(store.runningMachineCount) / Double(machineCount) : 0
            }
            return Double(machineCount) / Double(max(maxMachines, 1))
        }()

        let snapCount = store.usage?.snapshots ?? store.snapshots.count
        let maxSnaps = store.usage?.limits.maxSnapshots ?? store.currentOrg?.limits?.maxSnapshots ?? 5
        let snapProgress = maxSnaps > 0 ? Double(snapCount) / Double(maxSnaps) : 0

        let storedBytes = store.usage?.storedBytes ?? store.currentOrg?.usage?.storedBytes ?? 0
        let maxStoredGiB = store.usage?.limits.maxStoredGiB ?? store.currentOrg?.limits?.maxStoredGiB ?? 200
        let storedGiB = Double(storedBytes) / 1_073_741_824.0
        let storageProgress = maxStoredGiB > 0 ? storedGiB / Double(maxStoredGiB) : 0

        let costSource = store.usage?.cost ?? store.currentOrg?.usage
        let billing = BillingQuotaMetrics.compute(usageCost: costSource, orgLimits: store.currentOrg?.limits)
        let billingTint = billing.isOverBudget ? LiquidPalette.statusRed : LiquidPalette.statusGreen

        return LazyVGrid(columns: kpiColumns, spacing: 14) {
            MetricCard(
                title: "沙盒实例",
                value: "\(machineCount)",
                valueSuffix: isUnlimitedMachines ? "台" : "/ \(maxMachines)",
                subtitle: "当前运行中 \(store.runningMachineCount) 台",
                icon: "server.rack",
                tint: LiquidPalette.statusBlue,
                badgeText: isUnlimitedMachines ? "不限" : "\(Int(round(min(machineProgress, 1) * 100)))%",
                progress: machineProgress,
                showsThresholdWarning: !isUnlimitedMachines,
                footerIcon: "bolt.fill"
            )

            MetricCard(
                title: "快照数量",
                value: "\(snapCount)",
                valueSuffix: maxSnaps > 0 ? "/ \(maxSnaps)" : "份",
                subtitle: "支持秒级克隆与原地还原",
                icon: "externaldrive.badge.timemachine",
                tint: LiquidPalette.statusPurple,
                badgeText: maxSnaps > 0 ? "\(Int(round(min(snapProgress, 1) * 100)))%" : "不限",
                progress: snapProgress,
                showsThresholdWarning: maxSnaps > 0,
                footerIcon: "clock.arrow.circlepath"
            )

            MetricCard(
                title: "持久化存储",
                value: String(format: "%.2f", storedGiB),
                valueSuffix: maxStoredGiB > 0 ? "/ \(maxStoredGiB) GiB" : "GiB",
                subtitle: "已分配磁盘 \(store.usage?.allocatedDiskGiB ?? 0) GiB",
                icon: "internaldrive",
                tint: LiquidPalette.statusTeal,
                badgeText: maxStoredGiB > 0 ? "\(Int(round(min(storageProgress, 1) * 100)))%" : "不限",
                progress: storageProgress,
                showsThresholdWarning: maxStoredGiB > 0,
                footerIcon: "opticaldiscdrive"
            )

            MetricCard(
                title: "本月账单用量",
                value: billing.primaryValueText,
                valueSuffix: billing.suffixValueText,
                subtitle: billing.subtitleText,
                icon: "dollarsign.circle",
                tint: billingTint,
                badgeText: billing.badgeText,
                useSolidEmeraldBadge: !billing.isOverBudget,
                progress: billing.progress,
                showsThresholdWarning: billing.hasBudgetCap || billing.isOverBudget,
                footerIcon: "creditcard"
            )
        }
    }

    @ViewBuilder
    private var billingAndRuntimeSection: some View {
        if let cost = store.usage?.cost ?? store.currentOrg?.usage {
            let overage = cost.overageUSD ?? 0
            let periodLabel = formattedBillingPeriod(start: cost.periodStart, end: cost.periodEnd)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        GlassIconOrb(
                            systemImage: "chart.bar.xaxis",
                            tint: LiquidPalette.statusIndigo,
                            size: 28,
                            iconSize: 13,
                            cornerRadius: 8
                        )
                        Text("本月资源计量明细")
                            .font(.headline)
                            .foregroundStyle(LiquidPalette.textPrimary)
                    }

                    Spacer()

                    if let periodLabel {
                        Label(periodLabel, systemImage: "calendar")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(LiquidPalette.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .glassPill()
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Text("本月合计 \(Formatters.usd(cost.costUSD))")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(overage > 0 ? LiquidPalette.statusOrange : LiquidPalette.statusGreen)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .glassPill(tint: overage > 0 ? LiquidPalette.statusOrange : LiquidPalette.statusGreen)
                        .fixedSize(horizontal: true, vertical: false)
                }

                LazyVGrid(columns: breakdownColumns, spacing: 12) {
                    BillingBreakdownTile(
                        title: "vCPU 计算",
                        amountText: Formatters.usd(cost.vcpuUSD),
                        detailText: String(format: "%.2f vCPU·h", cost.vcpuHours ?? 0),
                        icon: "cpu",
                        tint: LiquidPalette.statusBlue
                    )

                    BillingBreakdownTile(
                        title: "内存占用",
                        amountText: Formatters.usd(cost.memUSD),
                        detailText: String(format: "%.2f GiB·h", cost.memGiBHours ?? 0),
                        icon: "memorychip",
                        tint: LiquidPalette.statusPurple
                    )

                    BillingBreakdownTile(
                        title: "存储计费",
                        amountText: Formatters.usd(cost.storageUSD),
                        detailText: String(format: "%.2f GiB·h", cost.storageGiBHours ?? 0),
                        icon: "internaldrive",
                        tint: LiquidPalette.statusTeal
                    )

                    BillingBreakdownTile(
                        title: "出站流量 (Egress)",
                        amountText: Formatters.usd(cost.egressUSD),
                        detailText: String(format: "%.3f GiB", cost.egressGiB ?? 0),
                        icon: "arrow.up.right.circle",
                        tint: LiquidPalette.statusOrange
                    )

                    BillingBreakdownTile(
                        title: "套餐赠送额度",
                        amountText: Formatters.usd(cost.allowanceUSD),
                        detailText: "剩余余额 \(Formatters.usd(cost.creditRemainingUSD ?? cost.creditsUSD))",
                        icon: "gift",
                        tint: LiquidPalette.statusGreen
                    )

                    BillingBreakdownTile(
                        title: "超出套餐费用",
                        amountText: Formatters.usd(cost.overageUSD),
                        detailText: overage > 0 ? "超出赠送额度按量计费" : "当前处于套餐额度内",
                        icon: overage > 0 ? "exclamationmark.triangle" : "checkmark.seal",
                        tint: overage > 0 ? LiquidPalette.statusOrange : LiquidPalette.statusGreen,
                        emphasizeBackground: overage > 0
                    )
                }
            }
            .padding(20)
            .glassCard(cornerRadius: 20)
        }
    }

    private func formattedBillingPeriod(start: String?, end: String?) -> String? {
        guard let start, let end, !start.isEmpty, !end.isEmpty else { return nil }
        let s = String(start.prefix(10))
        let e = String(end.prefix(10))
        return "\(s) ~ \(e)"
    }

    private var machineCostTableSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    GlassIconOrb(
                        systemImage: "clock.badge.checkmark",
                        tint: LiquidPalette.statusTeal,
                        size: 28,
                        iconSize: 13,
                        cornerRadius: 8
                    )
                    Text("沙盒运行时长与费用（含已删除沙盒）")
                        .font(.headline)
                        .foregroundStyle(LiquidPalette.textPrimary)
                }
                Spacer()
                Text(store.machineUsages.count > 20 ? "显示 20 / \(store.machineUsages.count) 条" : "共 \(store.machineUsages.count) 条记录")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(LiquidPalette.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .glassPill()
            }

            if store.machineUsages.isEmpty {
                Text("暂无本月沙盒计费记录")
                    .font(.subheadline)
                    .foregroundStyle(LiquidPalette.textSecondary)
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
                            .frame(width: 82, alignment: .center)
                        Text("计算费用")
                            .frame(width: 86, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiquidPalette.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)

                    Rectangle()
                        .fill(LiquidPalette.divider)
                        .frame(height: 1)

                    let maxRuntime = max(store.machineUsages.prefix(20).map(\.runningSeconds).max() ?? 1, 1)

                    ForEach(store.machineUsages.prefix(20)) { item in
                        let share = Double(item.runningSeconds) / Double(maxRuntime)

                        VStack(spacing: 7) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(item.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(LiquidPalette.textPrimary)
                                            .lineLimit(1)
                                        if item.deletedAt != nil {
                                            Text("已删除")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1.5)
                                                .foregroundStyle(LiquidPalette.statusNeutral)
                                                .glassPill()
                                        }
                                    }
                                    Text(item.id)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(LiquidPalette.textMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Text(Formatters.durationSeconds(item.runningSeconds))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(LiquidPalette.textPrimary)
                                    .frame(width: 95, alignment: .trailing)

                                Text("\(item.vcpuSeconds)s")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(LiquidPalette.textSecondary)
                                    .frame(width: 90, alignment: .trailing)

                                Group {
                                    if item.free {
                                        Text("免费额度")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2.5)
                                            .solidEmeraldPill()
                                    } else {
                                        Text("按量计费")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2.5)
                                            .foregroundStyle(LiquidPalette.statusBlue)
                                            .glassPill(tint: LiquidPalette.statusBlue)
                                    }
                                }
                                .frame(width: 82, alignment: .center)

                                Text(Formatters.usd(item.computeUSD))
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(item.free ? LiquidPalette.statusGreen : LiquidPalette.textPrimary)
                                    .frame(width: 86, alignment: .trailing)
                            }

                            LiquidProgressBar(
                                value: share,
                                tint: item.free ? LiquidPalette.statusGreen : LiquidPalette.statusBlue,
                                height: 5,
                                showsThresholdWarning: false
                            )
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .liquidWellInteractive(cornerRadius: 11, tint: item.free ? LiquidPalette.statusGreen : nil)
                    }
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 20)
    }
}

private struct BillingBreakdownTile: View {
    let title: String
    let amountText: String
    let detailText: String
    let icon: String
    let tint: Color
    var emphasizeBackground: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 16, alignment: .center)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiquidPalette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(amountText)
                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(emphasizeBackground ? tint : LiquidPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())

            Text(detailText)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(LiquidPalette.textMuted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidWellInteractive(cornerRadius: 12, tint: emphasizeBackground ? tint : nil)
    }
}
