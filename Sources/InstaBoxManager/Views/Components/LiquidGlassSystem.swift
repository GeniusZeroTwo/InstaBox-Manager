import AppKit
import SwiftUI

// MARK: - Liquid Motion Presets

enum LiquidMotion {
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.82)
    static let fluid = Animation.spring(response: 0.36, dampingFraction: 0.84)
    static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.72)
    static let ambient = Animation.easeInOut(duration: 12.0).repeatForever(autoreverses: true)
}

// MARK: - Ambient Refractive Backdrop

enum GlassStyleVariant: Equatable, Sendable {
    case regular
    case clear
}

/// Multi-layered atmospheric backdrop engineered for macOS Liquid Glass optical refraction.
/// Provides subtle living chromatic depth for glass edges to refract while preserving high text legibility.
struct GlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @ViewState private var ambientPhase = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            if !reduceTransparency {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        SIMD2<Float>(0.0, 0.0), SIMD2<Float>(0.52, 0.0), SIMD2<Float>(1.0, 0.0),
                        SIMD2<Float>(0.0, 0.48), SIMD2<Float>(0.48, 0.44), SIMD2<Float>(1.0, 0.52),
                        SIMD2<Float>(0.0, 1.0), SIMD2<Float>(0.50, 1.0), SIMD2<Float>(1.0, 1.0)
                    ],
                    colors: meshPalette
                )

                GeometryReader { proxy in
                    let w = proxy.size.width
                    let h = proxy.size.height
                    let driftX: CGFloat = (ambientPhase && !reduceMotion) ? 26 : -14
                    let driftY: CGFloat = (ambientPhase && !reduceMotion) ? 18 : -16

                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.blue.opacity(colorScheme == .dark ? 0.20 : 0.14),
                                        Color.indigo.opacity(colorScheme == .dark ? 0.08 : 0.05),
                                        .clear
                                    ],
                                    center: .center,
                                    startRadius: 12,
                                    endRadius: max(w, h) * 0.48
                                )
                            )
                            .frame(width: max(w * 0.65, 360), height: max(w * 0.65, 360))
                            .offset(x: -w * 0.22 + driftX, y: -h * 0.26 + driftY)

                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.cyan.opacity(colorScheme == .dark ? 0.15 : 0.11),
                                        Color.purple.opacity(colorScheme == .dark ? 0.08 : 0.05),
                                        .clear
                                    ],
                                    center: .center,
                                    startRadius: 12,
                                    endRadius: max(w, h) * 0.45
                                )
                            )
                            .frame(width: max(w * 0.58, 320), height: max(w * 0.58, 320))
                            .offset(x: w * 0.28 - driftX * 0.85, y: h * 0.24 - driftY * 0.9)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion, !reduceTransparency else { return }
            withAnimation(LiquidMotion.ambient) {
                ambientPhase = true
            }
        }
    }

    private var meshPalette: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.07, green: 0.10, blue: 0.18),
                Color(red: 0.08, green: 0.09, blue: 0.16),
                Color(red: 0.10, green: 0.08, blue: 0.19),
                Color(red: 0.06, green: 0.11, blue: 0.17),
                Color(red: 0.09, green: 0.12, blue: 0.22),
                Color(red: 0.08, green: 0.10, blue: 0.18),
                Color(red: 0.06, green: 0.08, blue: 0.13),
                Color(red: 0.07, green: 0.11, blue: 0.16),
                Color(red: 0.08, green: 0.09, blue: 0.15)
            ]
        } else {
            return [
                Color(red: 0.92, green: 0.95, blue: 1.00),
                Color(red: 0.95, green: 0.96, blue: 1.00),
                Color(red: 0.94, green: 0.93, blue: 0.99),
                Color(red: 0.94, green: 0.97, blue: 0.99),
                Color(red: 0.96, green: 0.97, blue: 1.00),
                Color(red: 0.93, green: 0.95, blue: 0.99),
                Color(red: 0.96, green: 0.97, blue: 0.99),
                Color(red: 0.94, green: 0.97, blue: 0.98),
                Color(red: 0.95, green: 0.95, blue: 0.99)
            ]
        }
    }
}

// MARK: - Primary Liquid Glass Modifiers

struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 18
    var variant: GlassStyleVariant = .regular
    var tint: Color? = nil
    var interactive: Bool = false
    var elevated: Bool = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if reduceTransparency {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay {
                    shape.strokeBorder(
                        .primary.opacity(contrast == .increased ? 0.34 : 0.16),
                        lineWidth: contrast == .increased ? 1.5 : 1
                    )
                }
        } else {
            let configuredGlass: Glass = {
                var g: Glass = (variant == .clear) ? .clear : .regular
                if let tint {
                    g = g.tint(tint)
                }
                if interactive {
                    g = g.interactive(true)
                }
                return g
            }()

            content
                .glassEffect(configuredGlass, in: shape)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(
                                    contrast == .increased
                                        ? 0.55
                                        : (colorScheme == .dark ? 0.24 : 0.62)
                                ),
                                .white.opacity(colorScheme == .dark ? 0.06 : 0.18),
                                .primary.opacity(contrast == .increased ? 0.24 : 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: contrast == .increased ? 1.2 : 0.75
                    )
                    .allowsHitTesting(false)
                }
                .shadow(
                    color: .black.opacity(elevated ? (colorScheme == .dark ? 0.22 : 0.06) : 0),
                    radius: elevated ? 16 : 0,
                    y: elevated ? 6 : 0
                )
        }
    }
}

struct GlassCapsulePillModifier: ViewModifier {
    var tint: Color? = nil
    var interactive: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background((tint ?? .secondary).opacity(0.16), in: Capsule())
                .overlay {
                    Capsule().strokeBorder((tint ?? .primary).opacity(0.28), lineWidth: 1)
                }
        } else {
            let glass: Glass = {
                var g: Glass = .regular
                if let tint {
                    g = g.tint(tint)
                }
                if interactive {
                    g = g.interactive(true)
                }
                return g
            }()

            content
                .glassEffect(glass, in: Capsule())
                .overlay {
                    if contrast == .increased {
                        Capsule()
                            .strokeBorder((tint ?? .primary).opacity(0.45), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

/// Translucent recessed slot used inside a Liquid Glass card so nested items
/// establish clean hierarchy without stacking heavy glass-on-glass blurs.
struct GlassWellModifier: ViewModifier {
    var cornerRadius: CGFloat = 11
    var tint: Color? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let baseFill: Color = {
            if reduceTransparency {
                return Color(nsColor: .windowBackgroundColor)
            }
            if let tint {
                return tint.opacity(colorScheme == .dark ? 0.13 : 0.09)
            }
            return colorScheme == .dark
                ? Color.white.opacity(0.055)
                : Color.black.opacity(0.032)
        }()

        content
            .background(baseFill, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            (tint ?? .white).opacity(colorScheme == .dark ? 0.14 : 0.45),
                            .primary.opacity(colorScheme == .dark ? 0.08 : 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
                .allowsHitTesting(false)
            }
    }
}

/// High-legibility translucent code/terminal surface harmonized with Liquid Glass containers.
struct GlassCodeCanvasModifier: ViewModifier {
    var cornerRadius: CGFloat = 12

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let fill: Color = {
            if reduceTransparency {
                return Color(nsColor: .textBackgroundColor)
            }
            return colorScheme == .dark
                ? Color(red: 0.04, green: 0.06, blue: 0.10).opacity(0.76)
                : Color.white.opacity(0.72)
        }()

        content
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            .primary.opacity(0.12),
                            .white.opacity(colorScheme == .dark ? 0.10 : 0.50)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )
                .allowsHitTesting(false)
            }
    }
}

extension View {
    func glassSurface(
        cornerRadius: CGFloat = 18,
        variant: GlassStyleVariant = .regular,
        tint: Color? = nil,
        interactive: Bool = false,
        elevated: Bool = true
    ) -> some View {
        modifier(
            GlassSurface(
                cornerRadius: cornerRadius,
                variant: variant,
                tint: tint,
                interactive: interactive,
                elevated: elevated
            )
        )
    }

    func glassCard(
        cornerRadius: CGFloat = 18,
        tint: Color? = nil,
        interactive: Bool = false,
        elevated: Bool = true
    ) -> some View {
        modifier(
            GlassSurface(
                cornerRadius: cornerRadius,
                variant: .regular,
                tint: tint,
                interactive: interactive,
                elevated: elevated
            )
        )
    }

    func glassPill(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassCapsulePillModifier(tint: tint, interactive: interactive))
    }

    func glassWell(cornerRadius: CGFloat = 11, tint: Color? = nil) -> some View {
        modifier(GlassWellModifier(cornerRadius: cornerRadius, tint: tint))
    }

    func glassCodeCanvas(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassCodeCanvasModifier(cornerRadius: cornerRadius))
    }

    /// Subtle spring hover elevation, micro-scale, and colored specular halo for interactive glass cards.
    func liquidHoverLift(
        scale: CGFloat = 1.012,
        liftY: CGFloat = -2,
        glowColor: Color = .accentColor
    ) -> some View {
        modifier(LiquidHoverLiftModifier(scale: scale, liftY: liftY, glowColor: glowColor))
    }

    /// Crisp hover brightening and tactile micro-response for recessed list/well rows.
    func liquidWellInteractive(cornerRadius: CGFloat = 11, tint: Color? = nil) -> some View {
        modifier(LiquidWellInteractiveModifier(cornerRadius: cornerRadius, tint: tint))
    }

    /// Staggered fluid entrance animation on appear (automatically bypassed under Reduce Motion).
    func liquidAppear(delay: Double = 0, offsetY: CGFloat = 10) -> some View {
        modifier(LiquidAppearModifier(delay: delay, offsetY: offsetY))
    }
}

// MARK: - Interactive Micro-Motion Modifiers

struct LivePulseDot: View {
    let color: Color
    var isPulsing: Bool = true
    var size: CGFloat = 7

    @ViewState private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isPulsing && !reduceMotion {
                Circle()
                    .stroke(color.opacity(pulse ? 0.0 : 0.65), lineWidth: 1.5)
                    .frame(width: size, height: size)
                    .scaleEffect(pulse ? 2.3 : 1.0)
                    .onAppear {
                        withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                            pulse = true
                        }
                    }
            }
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: isPulsing ? color.opacity(0.75) : .clear, radius: 4)
        }
        .frame(width: size + 2, height: size + 2)
    }
}

private struct LiquidHoverLiftModifier: ViewModifier {
    let scale: CGFloat
    let liftY: CGFloat
    let glowColor: Color

    @ViewState private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered && !reduceMotion ? scale : 1.0)
            .offset(y: isHovered && !reduceMotion ? liftY : 0)
            .shadow(
                color: isHovered ? glowColor.opacity(colorScheme == .dark ? 0.22 : 0.14) : .clear,
                radius: isHovered ? 20 : 0,
                y: isHovered ? 8 : 0
            )
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : LiquidMotion.snappy) {
                    isHovered = hovering
                }
            }
    }
}

private struct LiquidWellInteractiveModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    @ViewState private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .glassWell(cornerRadius: cornerRadius, tint: tint)
            .overlay {
                if isHovered {
                    shape
                        .fill((tint ?? Color.accentColor).opacity(colorScheme == .dark ? 0.08 : 0.05))
                        .overlay {
                            shape.strokeBorder((tint ?? Color.accentColor).opacity(0.28), lineWidth: 0.9)
                        }
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(isHovered && !reduceMotion ? 1.005 : 1.0)
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : LiquidMotion.snappy) {
                    isHovered = hovering
                }
            }
    }
}

private struct LiquidAppearModifier: ViewModifier {
    let delay: Double
    let offsetY: CGFloat

    @ViewState private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared || reduceMotion ? 1 : 0)
            .offset(y: (hasAppeared || reduceMotion) ? 0 : offsetY)
            .onAppear {
                guard !hasAppeared else { return }
                if reduceMotion {
                    hasAppeared = true
                } else {
                    withAnimation(LiquidMotion.fluid.delay(delay)) {
                        hasAppeared = true
                    }
                }
            }
    }
}

// MARK: - Refractive Icon Orb

struct GlassIconOrb: View {
    let systemImage: String
    var tint: Color = .accentColor
    var size: CGFloat = 34
    var iconSize: CGFloat = 15
    var cornerRadius: CGFloat = 11

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                if reduceTransparency {
                    shape.fill(tint.opacity(0.15))
                } else {
                    Color.clear
                        .glassEffect(.regular.tint(tint.opacity(0.20)), in: shape)
                }
            }
            .overlay {
                shape.strokeBorder(tint.opacity(0.24), lineWidth: 0.75)
            }
    }
}

// MARK: - Fluid Morphing Liquid Glass Segmented Picker

struct LiquidGlassSegmentItem<Value: Hashable & Sendable>: Identifiable {
    let value: Value
    let title: String
    var icon: String? = nil

    var id: Value { value }
}

/// Uses `GlassEffectContainer` + `glassEffectID` so the active selection capsule
/// physically morphs and refracts across options when switching segments.
struct LiquidGlassSegmentedPicker<Value: Hashable & Sendable>: View {
    let items: [LiquidGlassSegmentItem<Value>]
    @Binding var selection: Value
    var expandEqually: Bool = false
    var compact: Bool = false

    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: compact ? 2 : 4) {
                ForEach(items) { item in
                    let isSelected = selection == item.value
                    Button {
                        if reduceMotion {
                            selection = item.value
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
                                selection = item.value
                            }
                        }
                    } label: {
                        HStack(spacing: compact ? 4 : 5) {
                            if let icon = item.icon {
                                Image(systemName: icon)
                                    .font(.system(size: compact ? 11 : 12, weight: isSelected ? .semibold : .medium))
                                    .symbolEffect(.bounce.down, value: isSelected && !reduceMotion)
                            }
                            Text(item.title)
                                .font((compact ? Font.caption : Font.subheadline).weight(isSelected ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, compact ? 7 : 12)
                        .padding(.vertical, compact ? 5 : 6)
                        .frame(maxWidth: expandEqually ? .infinity : nil)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .contentShape(Capsule())
                        .background {
                            if isSelected {
                                if reduceTransparency {
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.20))
                                        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1))
                                } else {
                                    Capsule()
                                        .fill(.clear)
                                        .glassEffect(
                                            .regular.tint(Color.accentColor.opacity(0.26)).interactive(),
                                            in: Capsule()
                                        )
                                        .glassEffectID("activeSegment", in: glassNamespace)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(compact ? 3 : 4)
            .glassWell(cornerRadius: 999)
        }
    }
}

// MARK: - Ratio-Locked Resizable Liquid Split View

enum LiquidSplitPinnedSide: Sendable {
    case leading
    case trailing
}

/// A ratio-stable macOS horizontal split container that completely isolates pane geometry
/// from child intrinsic-size fluctuations (preventing `HSplitView` divider jumps when
/// switching selected instances or changing toolbar button layouts).
struct LiquidSplitView<Leading: View, Trailing: View>: View {
    let storageKey: String
    let pinnedSide: LiquidSplitPinnedSide
    let defaultWidth: CGFloat
    let minPinnedWidth: CGFloat
    let maxPinnedWidth: CGFloat
    let minFlexibleWidth: CGFloat
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    @ViewState private var pinnedWidth: CGFloat
    @ViewState private var dragStartWidth: CGFloat? = nil
    @ViewState private var isHoveringHandle = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let handleWidth: CGFloat = 10

    init(
        storageKey: String,
        pinnedSide: LiquidSplitPinnedSide = .leading,
        defaultWidth: CGFloat,
        minPinnedWidth: CGFloat,
        maxPinnedWidth: CGFloat,
        minFlexibleWidth: CGFloat = 360,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.storageKey = storageKey
        self.pinnedSide = pinnedSide
        self.defaultWidth = defaultWidth
        self.minPinnedWidth = minPinnedWidth
        self.maxPinnedWidth = maxPinnedWidth
        self.minFlexibleWidth = minFlexibleWidth
        self.leading = leading
        self.trailing = trailing

        let saved = UserDefaults.standard.double(forKey: storageKey)
        let initial = saved > 0 ? CGFloat(saved) : defaultWidth
        self._pinnedWidth = ViewState(wrappedValue: min(max(initial, minPinnedWidth), maxPinnedWidth))
    }

    var body: some View {
        GeometryReader { proxy in
            let totalWidth = max(proxy.size.width, 1)
            let totalHeight = max(proxy.size.height, 1)
            let maxAllowed = max(minPinnedWidth, min(maxPinnedWidth, totalWidth - handleWidth - minFlexibleWidth))
            let clampedPinned = min(max(pinnedWidth, minPinnedWidth), maxAllowed)
            let flexibleWidth = max(0, totalWidth - handleWidth - clampedPinned)

            let leadingWidth = pinnedSide == .leading ? clampedPinned : flexibleWidth
            let trailingWidth = pinnedSide == .leading ? flexibleWidth : clampedPinned

            HStack(spacing: 0) {
                leading()
                    .frame(width: leadingWidth, height: totalHeight, alignment: .topLeading)
                    .clipped()

                splitHandle(maxAllowed: maxAllowed)

                trailing()
                    .frame(width: trailingWidth, height: totalHeight, alignment: .topLeading)
                    .clipped()
            }
            .coordinateSpace(name: "LiquidSplitCoordinateSpace")
        }
        .onDisappear {
            if isHoveringHandle {
                NSCursor.pop()
                isHoveringHandle = false
            }
        }
    }

    private func splitHandle(maxAllowed: CGFloat) -> some View {
        let isActive = isHoveringHandle || dragStartWidth != nil

        return ZStack {
            Color.clear
            Capsule()
                .fill(
                    isActive
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.65 : 0.55)
                        : Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.12)
                )
                .frame(width: isActive ? 4 : 2.5, height: isActive ? 48 : 32)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isActive)
        }
        .frame(width: handleWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering && !isHoveringHandle {
                isHoveringHandle = true
                NSCursor.resizeLeftRight.push()
            } else if !hovering && isHoveringHandle {
                isHoveringHandle = false
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("LiquidSplitCoordinateSpace"))
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = pinnedWidth
                    }
                    let start = dragStartWidth ?? pinnedWidth
                    let delta = pinnedSide == .leading ? value.translation.width : -value.translation.width
                    pinnedWidth = min(max(start + delta, minPinnedWidth), maxAllowed)
                }
                .onEnded { _ in
                    dragStartWidth = nil
                    UserDefaults.standard.set(Double(pinnedWidth), forKey: storageKey)
                }
        )
        .onTapGesture(count: 2) {
            let resetValue = min(max(defaultWidth, minPinnedWidth), maxAllowed)
            if reduceMotion {
                pinnedWidth = resetValue
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    pinnedWidth = resetValue
                }
            }
            UserDefaults.standard.set(Double(resetValue), forKey: storageKey)
        }
        .help("左右拖动调整分栏宽度，双击恢复默认比例")
    }
}
