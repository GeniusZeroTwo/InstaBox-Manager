import AppKit
import SwiftUI

// MARK: - WCAG-Verified Adaptive Color Tokens (Obsidian-Emerald Multi-Color System)

public struct LiquidRGB: Equatable, Sendable {
    public let r: Double
    public let g: Double
    public let b: Double
    public let a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    public var color: Color {
        Color(nsColor: nsColor)
    }

    public func withAlpha(_ alpha: Double) -> LiquidRGB {
        LiquidRGB(r, g, b, alpha)
    }

    /// Alpha-composites this translucent color over an opaque background color in sRGB.
    public func composited(over bg: LiquidRGB) -> LiquidRGB {
        let inv = 1.0 - a
        return LiquidRGB(
            r * a + bg.r * inv,
            g * a + bg.g * inv,
            b * a + bg.b * inv,
            1.0
        )
    }

    /// WCAG 2.1 relative luminance (IEC 61966-2-1 transfer function).
    public var relativeLuminance: Double {
        func linearize(_ c: Double) -> Double {
            c <= 0.04045 ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    /// WCAG 2.1 contrast ratio between this color and another opaque color (1.0 ... 21.0).
    public func contrastRatio(against background: LiquidRGB) -> Double {
        let fg = a < 1.0 ? composited(over: background) : self
        let l1 = max(fg.relativeLuminance, background.relativeLuminance)
        let l2 = min(fg.relativeLuminance, background.relativeLuminance)
        return (l1 + 0.05) / (l2 + 0.05)
    }
}

/// High-contrast Obsidian-Emerald multi-color palette inspired by modern dark telemetry consoles.
/// Anchored around electric emerald green with vivid supporting accents (sky blue, violet, amber, teal, coral)
/// and crisp pure-white / obsidian-ink typography passing WCAG AAA on cards and solid emerald controls.
public enum LiquidPalette {
    // MARK: Raw sRGB Token Definitions (Shared by UI & Automated WCAG Self-Tests)

    // Deep jet obsidian canvas in Dark; fresh mint-porcelain in Light
    public static let backdropLight = LiquidRGB(0.918, 0.949, 0.930, 1.0)       // #EAF2ED
    public static let backdropDark = LiquidRGB(0.043, 0.055, 0.047, 1.0)        // #0B0E0C
    public static let backdropLightEdge = LiquidRGB(0.878, 0.930, 0.898, 1.0)   // #E0EDE5
    public static let backdropDarkEdge = LiquidRGB(0.059, 0.086, 0.071, 1.0)    // #0F1612

    // Sidebar surface
    public static let sidebarDark = LiquidRGB(0.075, 0.090, 0.080, 0.96)        // #131714
    public static let sidebarLight = LiquidRGB(0.955, 0.976, 0.963, 0.96)       // #F4F9F6

    // Elevated frosted cards (crisp separation against obsidian / mint canvas)
    public static let cardScrimLight = LiquidRGB(1.000, 1.000, 1.000, 0.90)
    public static let cardScrimDark = LiquidRGB(0.086, 0.106, 0.094, 0.90)      // #161B18
    public static let cardScrimLightHC = LiquidRGB(1.000, 1.000, 1.000, 0.97)
    public static let cardScrimDarkHC = LiquidRGB(0.075, 0.094, 0.082, 0.96)

    // Inner recessed tiles / wells (e.g. quota breakdowns, info cells)
    public static let wellFillLight = LiquidRGB(0.925, 0.953, 0.937, 0.94)      // #ECF3EF
    public static let wellFillDark = LiquidRGB(0.125, 0.149, 0.137, 0.92)       // #202623

    // Code & terminal canvases
    public static let codeCanvasLight = LiquidRGB(0.985, 0.996, 0.990, 0.96)
    public static let codeCanvasDark = LiquidRGB(0.039, 0.051, 0.043, 0.95)     // #0A0D0B

    // Pill bases
    public static let pillBaseLight = LiquidRGB(0.965, 0.988, 0.974, 0.92)
    public static let pillBaseDark = LiquidRGB(0.114, 0.141, 0.125, 0.90)       // #1D2420

    // Electric Emerald Signature Solid Fill + Obsidian Ink Foreground (~9.9:1 WCAG AAA!)
    public static let brandEmeraldSolid = LiquidRGB(0.133, 0.827, 0.400, 1.0)   // #22D366
    public static let brandEmeraldBright = LiquidRGB(0.180, 0.902, 0.467, 1.0)  // #2EE677
    public static let brandEmeraldDeep = LiquidRGB(0.098, 0.745, 0.345, 1.0)    // #19BE58
    public static let onBrandEmerald = LiquidRGB(0.020, 0.075, 0.039, 1.0)      // #05130A

    // Active segment capsule (solid electric emerald in both modes with jet-black text)
    public static let segmentActiveLight = brandEmeraldSolid
    public static let segmentActiveDark = brandEmeraldSolid

    // Ultra-crisp typography tokens
    public static let textPrimaryLight = LiquidRGB(0.031, 0.075, 0.051, 1.0)    // #08130D
    public static let textPrimaryDark = LiquidRGB(1.000, 1.000, 1.000, 1.0)     // #FFFFFF

    public static let textSecondaryLight = LiquidRGB(0.110, 0.192, 0.149, 1.0)  // #1C3126
    public static let textSecondaryDark = LiquidRGB(0.855, 0.902, 0.875, 1.0)   // #DAE6DF

    public static let textMutedLight = LiquidRGB(0.224, 0.318, 0.267, 1.0)      // #395144
    public static let textMutedDark = LiquidRGB(0.663, 0.737, 0.694, 1.0)       // #A9BCB1

    // Deep saturated fills for macOS white-text `.glassProminent` buttons (>= 5.0:1 with white text)
    public static let prominentGreen = LiquidRGB(0.016, 0.471, 0.227, 1.0)      // #04783A
    public static let prominentBlue = LiquidRGB(0.012, 0.412, 0.631, 1.0)       // #0369A1
    public static let prominentIndigo = LiquidRGB(0.263, 0.220, 0.792, 1.0)     // #4338CA
    public static let prominentOrange = LiquidRGB(0.706, 0.325, 0.035, 1.0)     // #B45309

    // Active macOS List selection highlight reference
    public static let selectionAccentRef = LiquidRGB(0.016, 0.471, 0.227, 1.0)
    public static let selectedRowPrimary = LiquidRGB(1.000, 1.000, 1.000, 1.0)
    public static let selectedRowSecondary = LiquidRGB(1.000, 1.000, 1.000, 0.92)
    public static let selectedRowMuted = LiquidRGB(1.000, 1.000, 1.000, 0.86)

    // Vivid Multi-Color Semantic Accents (Emerald-First + Sky, Gold, Violet, Teal, Rose, Coral)
    public static let statusGreenLight = LiquidRGB(0.016, 0.471, 0.227, 1.0)    // #04783A
    public static let statusGreenDark = LiquidRGB(0.173, 0.902, 0.447, 1.0)     // #2CE672

    public static let statusBlueLight = LiquidRGB(0.012, 0.412, 0.631, 1.0)     // #0369A1
    public static let statusBlueDark = LiquidRGB(0.220, 0.741, 0.973, 1.0)      // #38BDF8

    public static let statusOrangeLight = LiquidRGB(0.675, 0.302, 0.024, 1.0)   // #AC4D06
    public static let statusOrangeDark = LiquidRGB(0.984, 0.749, 0.141, 1.0)    // #FBBF24

    public static let statusRedLight = LiquidRGB(0.725, 0.110, 0.110, 1.0)      // #B91C1C
    public static let statusRedDark = LiquidRGB(1.000, 0.494, 0.569, 1.0)       // #FF7E91

    public static let statusPurpleLight = LiquidRGB(0.427, 0.157, 0.851, 1.0)   // #6D28D9
    public static let statusPurpleDark = LiquidRGB(0.816, 0.635, 1.000, 1.0)    // #D0A2FF

    public static let statusIndigoLight = LiquidRGB(0.263, 0.220, 0.792, 1.0)   // #4338CA
    public static let statusIndigoDark = LiquidRGB(0.647, 0.706, 0.988, 1.0)    // #A5B4FC

    public static let statusTealLight = LiquidRGB(0.059, 0.463, 0.431, 1.0)     // #0F766E
    public static let statusTealDark = LiquidRGB(0.176, 0.831, 0.749, 1.0)      // #2DD4BF

    public static let statusPinkLight = LiquidRGB(0.745, 0.094, 0.365, 1.0)     // #BE185D
    public static let statusPinkDark = LiquidRGB(0.976, 0.533, 0.769, 1.0)      // #F988C4

    public static let statusNeutralLight = LiquidRGB(0.176, 0.247, 0.208, 1.0)  // #2D3F35
    public static let statusNeutralDark = LiquidRGB(0.824, 0.871, 0.843, 1.0)   // #D2DED7

    public static let dividerLight = LiquidRGB(0.031, 0.075, 0.051, 0.11)
    public static let dividerDark = LiquidRGB(1.000, 1.000, 1.000, 0.11)

    public static let progressTrackLight = LiquidRGB(0.031, 0.075, 0.051, 0.11)
    public static let progressTrackDark = LiquidRGB(1.000, 1.000, 1.000, 0.12)

    // MARK: Adaptive SwiftUI Colors

    public static let textPrimary = adaptive(light: textPrimaryLight, dark: textPrimaryDark)
    public static let textSecondary = adaptive(
        light: textSecondaryLight,
        dark: textSecondaryDark,
        lightHC: textPrimaryLight,
        darkHC: textPrimaryDark
    )
    public static let textMuted = adaptive(
        light: textMutedLight,
        dark: textMutedDark,
        lightHC: textSecondaryLight,
        darkHC: textSecondaryDark
    )

    public static let statusGreen = adaptive(light: statusGreenLight, dark: statusGreenDark)
    public static let statusBlue = adaptive(light: statusBlueLight, dark: statusBlueDark)
    public static let statusOrange = adaptive(light: statusOrangeLight, dark: statusOrangeDark)
    public static let statusRed = adaptive(light: statusRedLight, dark: statusRedDark)
    public static let statusPurple = adaptive(light: statusPurpleLight, dark: statusPurpleDark)
    public static let statusIndigo = adaptive(light: statusIndigoLight, dark: statusIndigoDark)
    public static let statusTeal = adaptive(light: statusTealLight, dark: statusTealDark)
    public static let statusPink = adaptive(light: statusPinkLight, dark: statusPinkDark)
    public static let statusNeutral = adaptive(light: statusNeutralLight, dark: statusNeutralDark)

    public static let divider = adaptive(light: dividerLight, dark: dividerDark)
    public static let progressTrack = adaptive(light: progressTrackLight, dark: progressTrackDark)

    public static func rowPrimary(prominence: BackgroundProminence) -> Color {
        prominence == .increased ? selectedRowPrimary.color : textPrimary
    }

    public static func rowSecondary(prominence: BackgroundProminence) -> Color {
        prominence == .increased ? selectedRowSecondary.color : textSecondary
    }

    public static func rowMuted(prominence: BackgroundProminence) -> Color {
        prominence == .increased ? selectedRowMuted.color : textMuted
    }

    public static func adaptive(
        light: LiquidRGB,
        dark: LiquidRGB,
        lightHC: LiquidRGB? = nil,
        darkHC: LiquidRGB? = nil
    ) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [
                    .accessibilityHighContrastDarkAqua,
                    .accessibilityHighContrastVibrantDark,
                    .darkAqua,
                    .vibrantDark,
                    .accessibilityHighContrastAqua,
                    .accessibilityHighContrastVibrantLight,
                    .aqua,
                    .vibrantLight
                ])
                switch match {
                case .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
                    return (darkHC ?? dark).nsColor
                case .darkAqua, .vibrantDark:
                    return dark.nsColor
                case .accessibilityHighContrastAqua, .accessibilityHighContrastVibrantLight:
                    return (lightHC ?? light).nsColor
                default:
                    return light.nsColor
                }
            }
        )
    }
}

// MARK: - Liquid Motion Presets

enum LiquidMotion {
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.84)
    static let fluid = Animation.spring(response: 0.34, dampingFraction: 0.86)
    static let bouncy = Animation.spring(response: 0.40, dampingFraction: 0.76)
    static let ambient = Animation.easeInOut(duration: 14.0).repeatForever(autoreverses: true)
}

// MARK: - Ambient Obsidian-Emerald Backdrop

enum GlassStyleVariant: Equatable, Sendable {
    case regular
    case clear
}

/// Deep obsidian canvas with luminous emerald & multi-color atmospheric glows in Dark Mode,
/// and crisp mint-porcelain with soft emerald/sky/violet blooms in Light Mode.
struct GlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @ViewState private var ambientPhase = false

    var body: some View {
        ZStack {
            (colorScheme == .dark ? LiquidPalette.backdropDark.color : LiquidPalette.backdropLight.color)

            if !reduceTransparency {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        SIMD2<Float>(0.0, 0.0), SIMD2<Float>(0.50, 0.0), SIMD2<Float>(1.0, 0.0),
                        SIMD2<Float>(0.0, 0.50), SIMD2<Float>(0.48, 0.45), SIMD2<Float>(1.0, 0.50),
                        SIMD2<Float>(0.0, 1.0), SIMD2<Float>(0.50, 1.0), SIMD2<Float>(1.0, 1.0)
                    ],
                    colors: meshPalette
                )

                GeometryReader { proxy in
                    let w = proxy.size.width
                    let h = proxy.size.height
                    let driftX: CGFloat = (ambientPhase && !reduceMotion) ? 24 : -14
                    let driftY: CGFloat = (ambientPhase && !reduceMotion) ? 16 : -14

                    ZStack {
                        // Primary Electric Emerald bloom
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        LiquidPalette.brandEmeraldSolid.color.opacity(colorScheme == .dark ? 0.16 : 0.11),
                                        LiquidPalette.statusTeal.opacity(colorScheme == .dark ? 0.06 : 0.04),
                                        .clear
                                    ],
                                    center: .center,
                                    startRadius: 12,
                                    endRadius: max(w, h) * 0.48
                                )
                            )
                            .frame(width: max(w * 0.65, 360), height: max(w * 0.65, 360))
                            .offset(x: -w * 0.22 + driftX, y: -h * 0.26 + driftY)

                        // Secondary Sky + Orchid accent bloom for colorful optical depth
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        LiquidPalette.statusBlue.opacity(colorScheme == .dark ? 0.11 : 0.08),
                                        LiquidPalette.statusPurple.opacity(colorScheme == .dark ? 0.07 : 0.04),
                                        .clear
                                    ],
                                    center: .center,
                                    startRadius: 12,
                                    endRadius: max(w, h) * 0.45
                                )
                            )
                            .frame(width: max(w * 0.56, 320), height: max(w * 0.56, 320))
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
                Color(red: 0.043, green: 0.068, blue: 0.055),
                Color(red: 0.045, green: 0.056, blue: 0.050),
                Color(red: 0.048, green: 0.058, blue: 0.068),
                Color(red: 0.040, green: 0.062, blue: 0.050),
                Color(red: 0.050, green: 0.074, blue: 0.062),
                Color(red: 0.048, green: 0.055, blue: 0.065),
                Color(red: 0.038, green: 0.048, blue: 0.042),
                Color(red: 0.042, green: 0.058, blue: 0.050),
                Color(red: 0.046, green: 0.050, blue: 0.058)
            ]
        } else {
            return [
                Color(red: 0.878, green: 0.942, blue: 0.908),
                Color(red: 0.916, green: 0.952, blue: 0.936),
                Color(red: 0.902, green: 0.935, blue: 0.962),
                Color(red: 0.896, green: 0.948, blue: 0.922),
                Color(red: 0.930, green: 0.960, blue: 0.946),
                Color(red: 0.908, green: 0.938, blue: 0.958),
                Color(red: 0.918, green: 0.950, blue: 0.932),
                Color(red: 0.902, green: 0.946, blue: 0.926),
                Color(red: 0.914, green: 0.934, blue: 0.954)
            ]
        }
    }
}

// MARK: - Electric Emerald Primary Button Style (Jet-Black Text on Vivid Emerald, ~9.9:1 Contrast)

struct EmeraldPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(LiquidPalette.onBrandEmerald.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isHovered
                                ? [LiquidPalette.brandEmeraldBright.color, LiquidPalette.brandEmeraldSolid.color]
                                : [LiquidPalette.brandEmeraldSolid.color, LiquidPalette.brandEmeraldDeep.color],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.42 : 0.24), lineWidth: 0.9)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: LiquidPalette.brandEmeraldSolid.color.opacity(isHovered ? 0.36 : 0.22),
                radius: isHovered ? 14 : 8,
                y: 3
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.45)
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : LiquidMotion.snappy) {
                    isHovered = hovering
                }
            }
            .animation(reduceMotion ? nil : LiquidMotion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == EmeraldPrimaryButtonStyle {
    static var emeraldPrimary: EmeraldPrimaryButtonStyle { EmeraldPrimaryButtonStyle() }
}

// MARK: - Primary Liquid Glass Modifiers

struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 18
    var variant: GlassStyleVariant = .regular
    var tint: Color? = nil
    var accentTopColor: Color? = nil
    var interactive: Bool = false
    var elevated: Bool = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        let scrimColor: Color = {
            if reduceTransparency || contrast == .increased {
                return (colorScheme == .dark ? LiquidPalette.cardScrimDarkHC : LiquidPalette.cardScrimLightHC).color
            }
            return (colorScheme == .dark ? LiquidPalette.cardScrimDark : LiquidPalette.cardScrimLight).color
        }()

        let borderGradient = LinearGradient(
            colors: {
                if let accentTopColor {
                    return [
                        accentTopColor.opacity(colorScheme == .dark ? 0.58 : 0.48),
                        colorScheme == .dark ? Color.white.opacity(0.11) : Color(red: 0.03, green: 0.08, blue: 0.05).opacity(0.10),
                        colorScheme == .dark ? Color.white.opacity(0.14) : Color(red: 0.03, green: 0.08, blue: 0.05).opacity(0.14)
                    ]
                }
                return colorScheme == .dark
                    ? [
                        Color.white.opacity(contrast == .increased ? 0.36 : 0.18),
                        Color.white.opacity(0.07),
                        Color.white.opacity(contrast == .increased ? 0.22 : 0.11)
                    ]
                    : [
                        Color.white.opacity(0.95),
                        Color(red: 0.03, green: 0.08, blue: 0.05).opacity(contrast == .increased ? 0.22 : 0.10),
                        Color(red: 0.03, green: 0.08, blue: 0.05).opacity(contrast == .increased ? 0.28 : 0.14)
                    ]
            }(),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        if reduceTransparency {
            content
                .background(scrimColor, in: shape)
                .overlay(alignment: .top) {
                    if let accentTopColor {
                        accentTopStrip(accentTopColor, cornerRadius: cornerRadius)
                    }
                }
                .overlay {
                    shape.strokeBorder(borderGradient, lineWidth: contrast == .increased ? 1.5 : 1.0)
                        .allowsHitTesting(false)
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
                .background(scrimColor, in: shape)
                .glassEffect(configuredGlass, in: shape)
                .overlay(alignment: .top) {
                    if let accentTopColor {
                        accentTopStrip(accentTopColor, cornerRadius: cornerRadius)
                    }
                }
                .overlay {
                    shape.strokeBorder(borderGradient, lineWidth: contrast == .increased ? 1.25 : 0.95)
                        .allowsHitTesting(false)
                }
                .shadow(
                    color: .black.opacity(elevated ? (colorScheme == .dark ? 0.36 : 0.08) : 0),
                    radius: elevated ? 16 : 0,
                    y: elevated ? 6 : 0
                )
        }
    }

    private func accentTopStrip(_ color: Color, cornerRadius: CGFloat) -> some View {
        LinearGradient(
            colors: [color.opacity(0.0), color.opacity(0.85), color.opacity(0.0)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 2.5)
        .padding(.horizontal, max(cornerRadius * 0.8, 12))
        .allowsHitTesting(false)
    }
}

struct GlassCapsulePillModifier: ViewModifier {
    var tint: Color? = nil
    var solidEmerald: Bool = false
    var interactive: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if solidEmerald {
            content
                .foregroundStyle(LiquidPalette.onBrandEmerald.color)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [LiquidPalette.brandEmeraldBright.color, LiquidPalette.brandEmeraldSolid.color],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
        } else {
            let baseScrim: Color = colorScheme == .dark
                ? LiquidPalette.pillBaseDark.color
                : LiquidPalette.pillBaseLight.color
            let borderColor: Color = {
                if let tint {
                    return tint.opacity(colorScheme == .dark ? 0.55 : 0.42)
                }
                return colorScheme == .dark
                    ? Color.white.opacity(contrast == .increased ? 0.38 : 0.16)
                    : Color(red: 0.03, green: 0.08, blue: 0.05).opacity(contrast == .increased ? 0.30 : 0.15)
            }()

            if reduceTransparency {
                content
                    .background {
                        ZStack {
                            Capsule().fill(baseScrim)
                            if let tint {
                                Capsule().fill(tint.opacity(colorScheme == .dark ? 0.20 : 0.12))
                            }
                        }
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(borderColor, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
            } else {
                let glass: Glass = interactive ? .regular.interactive(true) : .regular

                content
                    .background {
                        ZStack {
                            Capsule().fill(baseScrim)
                            if let tint {
                                Capsule().fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.10))
                            }
                        }
                    }
                    .glassEffect(glass, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(borderColor, lineWidth: contrast == .increased ? 1.15 : 0.9)
                            .allowsHitTesting(false)
                    }
            }
        }
    }
}

/// Crisp recessed tile used inside cards (inspired by high-contrast graphite dashboard sub-cards).
struct GlassWellModifier: ViewModifier {
    var cornerRadius: CGFloat = 11
    var tint: Color? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let baseFill: Color = {
            if reduceTransparency {
                return colorScheme == .dark
                    ? LiquidPalette.wellFillDark.withAlpha(0.98).color
                    : LiquidPalette.wellFillLight.withAlpha(0.98).color
            }
            return colorScheme == .dark
                ? LiquidPalette.wellFillDark.color
                : LiquidPalette.wellFillLight.color
        }()

        content
            .background {
                ZStack {
                    shape.fill(baseFill)
                    if let tint {
                        shape.fill(tint.opacity(colorScheme == .dark ? 0.16 : 0.09))
                    }
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: {
                            if let tint {
                                return [
                                    tint.opacity(colorScheme == .dark ? 0.44 : 0.34),
                                    tint.opacity(colorScheme == .dark ? 0.22 : 0.18)
                                ]
                            }
                            return colorScheme == .dark
                                ? [
                                    Color.white.opacity(contrast == .increased ? 0.28 : 0.13),
                                    Color.white.opacity(contrast == .increased ? 0.18 : 0.07)
                                ]
                                : [
                                    Color(red: 0.03, green: 0.08, blue: 0.05).opacity(contrast == .increased ? 0.22 : 0.10),
                                    Color(red: 0.03, green: 0.08, blue: 0.05).opacity(contrast == .increased ? 0.26 : 0.13)
                                ]
                        }(),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: contrast == .increased ? 1.15 : 0.85
                )
                .allowsHitTesting(false)
            }
    }
}

/// High-legibility obsidian/porcelain code & terminal canvas.
struct GlassCodeCanvasModifier: ViewModifier {
    var cornerRadius: CGFloat = 12

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let fill: Color = {
            if reduceTransparency {
                return colorScheme == .dark
                    ? LiquidPalette.codeCanvasDark.withAlpha(1.0).color
                    : LiquidPalette.codeCanvasLight.withAlpha(1.0).color
            }
            return colorScheme == .dark
                ? LiquidPalette.codeCanvasDark.color
                : LiquidPalette.codeCanvasLight.color
        }()

        content
            .foregroundStyle(LiquidPalette.textPrimary)
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(
                    colorScheme == .dark
                        ? LiquidPalette.statusGreen.opacity(contrast == .increased ? 0.35 : 0.18)
                        : Color(red: 0.03, green: 0.08, blue: 0.05).opacity(contrast == .increased ? 0.28 : 0.15),
                    lineWidth: contrast == .increased ? 1.2 : 0.9
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
        accentTopColor: Color? = nil,
        interactive: Bool = false,
        elevated: Bool = true
    ) -> some View {
        modifier(
            GlassSurface(
                cornerRadius: cornerRadius,
                variant: variant,
                tint: tint,
                accentTopColor: accentTopColor,
                interactive: interactive,
                elevated: elevated
            )
        )
    }

    func glassCard(
        cornerRadius: CGFloat = 18,
        tint: Color? = nil,
        accentTopColor: Color? = nil,
        interactive: Bool = false,
        elevated: Bool = true
    ) -> some View {
        modifier(
            GlassSurface(
                cornerRadius: cornerRadius,
                variant: .regular,
                tint: tint,
                accentTopColor: accentTopColor,
                interactive: interactive,
                elevated: elevated
            )
        )
    }

    func glassPill(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassCapsulePillModifier(tint: tint, solidEmerald: false, interactive: interactive))
    }

    func solidEmeraldPill() -> some View {
        modifier(GlassCapsulePillModifier(tint: nil, solidEmerald: true, interactive: false))
    }

    func glassWell(cornerRadius: CGFloat = 11, tint: Color? = nil) -> some View {
        modifier(GlassWellModifier(cornerRadius: cornerRadius, tint: tint))
    }

    func glassCodeCanvas(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassCodeCanvasModifier(cornerRadius: cornerRadius))
    }

    func liquidHoverLift(
        scale: CGFloat = 1.0,
        liftY: CGFloat = -1.5,
        glowColor: Color = LiquidPalette.statusGreen
    ) -> some View {
        modifier(LiquidHoverLiftModifier(scale: scale, liftY: liftY, glowColor: glowColor))
    }

    func liquidWellInteractive(cornerRadius: CGFloat = 11, tint: Color? = nil) -> some View {
        modifier(LiquidWellInteractiveModifier(cornerRadius: cornerRadius, tint: tint))
    }

    func liquidAppear(delay: Double = 0, offsetY: CGFloat = 10) -> some View {
        modifier(LiquidAppearModifier(delay: delay, offsetY: offsetY))
    }
}

// MARK: - Unified High-Contrast Luminous Progress Track

struct LiquidProgressBar: View {
    let value: Double
    var tint: Color = LiquidPalette.statusGreen
    var height: CGFloat = 7
    var showsThresholdWarning: Bool = true
    var warningThreshold: Double = 0.85
    var criticalThreshold: Double = 0.95

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var clamped: Double {
        min(max(value, 0), 1)
    }

    static func resolvedTint(
        value: Double,
        baseTint: Color,
        showsThresholdWarning: Bool = true,
        warningThreshold: Double = 0.85,
        criticalThreshold: Double = 0.95
    ) -> Color {
        guard showsThresholdWarning else { return baseTint }
        let clamped = min(max(value, 0), 1)
        if clamped >= criticalThreshold { return LiquidPalette.statusRed }
        if clamped >= warningThreshold { return LiquidPalette.statusOrange }
        return baseTint
    }

    private var effectiveTint: Color {
        Self.resolvedTint(
            value: clamped,
            baseTint: tint,
            showsThresholdWarning: showsThresholdWarning,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = max(proxy.size.width, 0)
            let fillWidth = clamped > 0 ? max(height, trackWidth * clamped) : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LiquidPalette.progressTrack)

                if fillWidth > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [effectiveTint, effectiveTint.opacity(0.78)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(
                            color: effectiveTint.opacity(colorScheme == .dark ? 0.45 : 0.20),
                            radius: 5,
                            y: 0
                        )
                        .frame(width: min(fillWidth, trackWidth))
                }
            }
            .animation(reduceMotion ? nil : LiquidMotion.fluid, value: clamped)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("使用进度")
        .accessibilityValue("\(Int(round(clamped * 100)))%")
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
                    .stroke(color.opacity(pulse ? 0.0 : 0.72), lineWidth: 1.5)
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
                .shadow(color: isPulsing ? color.opacity(0.70) : .clear, radius: 4)
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
            .scaleEffect(isHovered && !reduceMotion && scale != 1.0 ? scale : 1.0)
            .offset(y: isHovered && !reduceMotion ? liftY : 0)
            .shadow(
                color: isHovered ? glowColor.opacity(colorScheme == .dark ? 0.28 : 0.16) : .clear,
                radius: isHovered ? 20 : 0,
                y: isHovered ? 7 : 0
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
        let activeColor = tint ?? LiquidPalette.statusGreen
        content
            .glassWell(cornerRadius: cornerRadius, tint: tint)
            .overlay {
                if isHovered {
                    shape
                        .fill(activeColor.opacity(colorScheme == .dark ? 0.12 : 0.07))
                        .overlay {
                            shape.strokeBorder(activeColor.opacity(colorScheme == .dark ? 0.52 : 0.38), lineWidth: 1.0)
                        }
                        .allowsHitTesting(false)
                }
            }
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

// MARK: - Vivid Colorful Icon Orb

struct GlassIconOrb: View {
    let systemImage: String
    var tint: Color = LiquidPalette.statusGreen
    var size: CGFloat = 34
    var iconSize: CGFloat = 15
    var cornerRadius: CGFloat = 11

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.backgroundProminence) private var backgroundProminence

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isProminentBg = backgroundProminence == .increased
        let iconColor: Color = isProminentBg ? .white : tint
        let fillColor: Color = isProminentBg
            ? Color.white.opacity(0.22)
            : tint.opacity(colorScheme == .dark ? 0.24 : 0.14)
        let borderColor: Color = isProminentBg
            ? Color.white.opacity(0.45)
            : tint.opacity(colorScheme == .dark ? 0.48 : 0.32)

        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(iconColor)
            .frame(width: size, height: size)
            .background {
                ZStack {
                    shape.fill(fillColor)
                    if !reduceTransparency && !isProminentBg {
                        Color.clear
                            .glassEffect(.regular, in: shape)
                    }
                }
            }
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: 0.95)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Electric Emerald Fluid Segmented Picker

struct LiquidGlassSegmentItem<Value: Hashable & Sendable>: Identifiable {
    let value: Value
    let title: String
    var icon: String? = nil

    var id: Value { value }
}

/// Active selection morphs smoothly as a solid electric emerald pill with high-contrast jet-black text (~9.9:1).
struct LiquidGlassSegmentedPicker<Value: Hashable & Sendable>: View {
    let items: [LiquidGlassSegmentItem<Value>]
    @Binding var selection: Value
    var expandEqually: Bool = false
    var compact: Bool = false

    @Namespace private var glassNamespace
    @ViewState private var hoveredValue: Value? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: compact ? 2 : 4) {
                ForEach(items) { item in
                    let isSelected = selection == item.value
                    let isHovered = hoveredValue == item.value && !isSelected

                    Button {
                        if reduceMotion {
                            selection = item.value
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                selection = item.value
                            }
                        }
                    } label: {
                        HStack(spacing: compact ? 4 : 5) {
                            if let icon = item.icon {
                                Image(systemName: icon)
                                    .font(.system(size: compact ? 11 : 12, weight: isSelected ? .bold : .medium))
                                    .symbolEffect(.bounce.down, value: isSelected && !reduceMotion)
                            }
                            Text(item.title)
                                .font((compact ? Font.caption : Font.subheadline).weight(isSelected ? .bold : .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, compact ? 8 : 12)
                        .padding(.vertical, compact ? 5 : 6)
                        .frame(maxWidth: expandEqually ? .infinity : nil)
                        .foregroundStyle(isSelected ? LiquidPalette.onBrandEmerald.color : LiquidPalette.textSecondary)
                        .contentShape(Capsule())
                        .background {
                            if isSelected {
                                let emeraldFill = LinearGradient(
                                    colors: [LiquidPalette.brandEmeraldBright.color, LiquidPalette.brandEmeraldSolid.color],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                if reduceTransparency {
                                    Capsule()
                                        .fill(emeraldFill)
                                } else {
                                    Capsule()
                                        .fill(emeraldFill)
                                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.32), lineWidth: 0.8))
                                        .shadow(color: LiquidPalette.brandEmeraldSolid.color.opacity(0.32), radius: 7, y: 2)
                                        .glassEffectID("activeSegment", in: glassNamespace)
                                }
                            } else if isHovered {
                                Capsule()
                                    .fill(LiquidPalette.statusGreen.opacity(colorScheme == .dark ? 0.14 : 0.10))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredValue = hovering ? item.value : (hoveredValue == item.value ? nil : hoveredValue)
                    }
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
                        ? LiquidPalette.brandEmeraldSolid.color
                        : (colorScheme == .dark ? Color.white.opacity(0.20) : Color(red: 0.03, green: 0.08, blue: 0.05).opacity(0.20))
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
