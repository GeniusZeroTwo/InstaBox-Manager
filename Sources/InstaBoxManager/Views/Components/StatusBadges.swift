import SwiftUI

struct StateBadge: View {
    let state: MachineState
    var operation: OperationItem? = nil

    private var isSolidRunning: Bool {
        operation == nil && state == .running
    }

    private var color: Color {
        if operation != nil || state.isTransitioning {
            return LiquidPalette.statusOrange
        }
        switch state {
        case .running: return LiquidPalette.statusGreen
        case .suspended: return LiquidPalette.statusIndigo
        case .stopped: return LiquidPalette.statusNeutral
        case .error: return LiquidPalette.statusRed
        default: return LiquidPalette.statusNeutral
        }
    }

    var body: some View {
        Group {
            if isSolidRunning {
                HStack(spacing: 5) {
                    Circle()
                        .fill(LiquidPalette.onBrandEmerald.color)
                        .frame(width: 6.5, height: 6.5)
                    Text(state.displayName)
                        .font(.caption.weight(.bold))
                        .contentTransition(.interpolate)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .solidEmeraldPill()
            } else {
                HStack(spacing: 5) {
                    if operation != nil || state.isTransitioning {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        LivePulseDot(color: color, isPulsing: false, size: 7)
                    }
                    Text(operation != nil ? "\(opLabel(operation!.type))中…" : state.displayName)
                        .font(.caption.weight(.semibold))
                        .contentTransition(.interpolate)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .foregroundStyle(color)
                .glassPill(tint: color)
            }
        }
        .animation(LiquidMotion.snappy, value: state)
        .animation(LiquidMotion.snappy, value: operation?.id)
    }

    private func opLabel(_ type: String) -> String {
        switch type {
        case "create": return "创建"
        case "start": return "启动"
        case "stop": return "停止"
        case "suspend": return "暂停"
        case "resume": return "恢复"
        case "delete": return "删除"
        case "restore": return "还原"
        case "resize": return "扩容"
        default: return type
        }
    }
}

struct TierBadge: View {
    let tier: String

    private var isFreeOrEmerald: Bool {
        tier.lowercased() == "free"
    }

    private var color: Color {
        switch tier.lowercased() {
        case "free": return LiquidPalette.statusGreen
        case "pro": return LiquidPalette.statusBlue
        case "builder": return LiquidPalette.statusPurple
        case "team": return LiquidPalette.statusOrange
        case "enterprise": return LiquidPalette.statusPink
        default: return LiquidPalette.statusGreen
        }
    }

    var body: some View {
        if isFreeOrEmerald {
            Text(tier.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 2.5)
                .solidEmeraldPill()
        } else {
            Text(tier.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 2.5)
                .foregroundStyle(color)
                .glassPill(tint: color)
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    var valueSuffix: String? = nil
    let subtitle: String
    let icon: String
    var tint: Color = LiquidPalette.statusGreen
    var badgeText: String? = nil
    var badgeTint: Color? = nil
    var useSolidEmeraldBadge: Bool = false
    var progress: Double? = nil
    var showsThresholdWarning: Bool = true
    var footerIcon: String? = nil

    var body: some View {
        let normalizedProgress = min(max(progress ?? 0, 0), 1)
        let resolvedBarTint = LiquidProgressBar.resolvedTint(
            value: normalizedProgress,
            baseTint: tint,
            showsThresholdWarning: showsThresholdWarning
        )
        let effectiveBadgeTint = badgeTint ?? resolvedBarTint

        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                GlassIconOrb(systemImage: icon, tint: tint, size: 28, iconSize: 12.5, cornerRadius: 9)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiquidPalette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badgeText, !badgeText.isEmpty {
                    if useSolidEmeraldBadge {
                        Text(badgeText)
                            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .solidEmeraldPill()
                            .fixedSize()
                    } else {
                        Text(badgeText)
                            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(effectiveBadgeTint)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .glassPill(tint: effectiveBadgeTint)
                            .fixedSize()
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 25, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(LiquidPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .contentTransition(.numericText())

                if let valueSuffix, !valueSuffix.isEmpty {
                    Text(valueSuffix)
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(LiquidPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.80)
                }
            }
            .animation(LiquidMotion.fluid, value: value)

            LiquidProgressBar(
                value: normalizedProgress,
                tint: tint,
                height: 7,
                showsThresholdWarning: showsThresholdWarning
            )

            Spacer(minLength: 2)

            HStack(spacing: 5) {
                if let footerIcon {
                    Image(systemName: footerIcon)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(effectiveBadgeTint)
                        .accessibilityHidden(true)
                }
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LiquidPalette.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .help(subtitle)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(cornerRadius: 18, tint: tint.opacity(0.06), accentTopColor: tint, interactive: true)
        .liquidHoverLift(liftY: -2, glowColor: tint)
    }
}
