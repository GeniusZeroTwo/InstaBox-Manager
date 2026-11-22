import SwiftUI
import WebKit

struct StateBadge: View {
    let state: MachineState
    var operation: OperationItem? = nil

    private var color: Color {
        if operation != nil || state.isTransitioning {
            return .orange
        }
        switch state {
        case .running: return .green
        case .suspended: return .indigo
        case .stopped: return .secondary
        case .error: return .red
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if operation != nil || state.isTransitioning {
                ProgressView()
                    .controlSize(.mini)
            } else {
                LivePulseDot(color: color, isPulsing: state == .running, size: 7)
            }
            Text(operation != nil ? "\(opLabel(operation!.type))中…" : state.displayName)
                .font(.caption.weight(.semibold))
                .contentTransition(.interpolate)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3.5)
        .foregroundStyle(color)
        .glassPill(tint: color.opacity(0.20))
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

    private var color: Color {
        switch tier.lowercased() {
        case "pro": return .blue
        case "builder": return .purple
        case "team": return .orange
        case "enterprise": return .pink
        default: return .secondary
        }
    }

    var body: some View {
        Text(tier.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 2.5)
            .foregroundStyle(color)
            .glassPill(tint: color.opacity(0.22))
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    var tint: Color = .accentColor
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                GlassIconOrb(systemImage: icon, tint: tint, size: 32, iconSize: 14, cornerRadius: 10)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(LiquidMotion.fluid, value: value)

            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(progress > 0.85 ? .orange : tint)
                    .animation(LiquidMotion.fluid, value: progress)
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20, tint: tint.opacity(0.06), interactive: true)
        .liquidHoverLift(scale: 1.016, liftY: -2.5, glowColor: tint)
    }
}

struct RemoteDesktopWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}
