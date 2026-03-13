import AppKit
import SwiftUI

func forgeColor(
    lightRed: Double,
    lightGreen: Double,
    lightBlue: Double,
    darkRed: Double,
    darkGreen: Double,
    darkBlue: Double,
    alpha: Double = 1.0
) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua]) ?? .aqua
        if bestMatch == .darkAqua {
            return NSColor(
                red: darkRed,
                green: darkGreen,
                blue: darkBlue,
                alpha: alpha
            )
        }
        return NSColor(
            red: lightRed,
            green: lightGreen,
            blue: lightBlue,
            alpha: alpha
        )
    })
}

let appAccent = forgeColor(
    lightRed: 0.84, lightGreen: 0.39, lightBlue: 0.05,
    darkRed: 0.94, darkGreen: 0.52, darkBlue: 0.16
)
let forgeGlow = forgeColor(
    lightRed: 0.95, lightGreen: 0.66, lightBlue: 0.24,
    darkRed: 0.99, darkGreen: 0.77, darkBlue: 0.43
)
let panelBackground = forgeColor(
    lightRed: 0.96, lightGreen: 0.92, lightBlue: 0.88,
    darkRed: 0.16, darkGreen: 0.10, darkBlue: 0.08
)
let sidebarBackground = forgeColor(
    lightRed: 0.92, lightGreen: 0.88, lightBlue: 0.83,
    darkRed: 0.12, darkGreen: 0.08, darkBlue: 0.06
)
let canvasBackground = forgeColor(
    lightRed: 0.99, lightGreen: 0.97, lightBlue: 0.94,
    darkRed: 0.09, darkGreen: 0.06, darkBlue: 0.05
)
let inputBackground = forgeColor(
    lightRed: 1.0, lightGreen: 0.98, lightBlue: 0.95,
    darkRed: 0.12, darkGreen: 0.08, darkBlue: 0.06
)
let borderColor = forgeColor(
    lightRed: 0.79, lightGreen: 0.49, lightBlue: 0.22,
    darkRed: 0.69, darkGreen: 0.38, darkBlue: 0.16,
    alpha: 0.26
)
let forgeBackdrop = LinearGradient(
    colors: [
        forgeColor(
            lightRed: 0.96, lightGreen: 0.91, lightBlue: 0.82,
            darkRed: 0.17, darkGreen: 0.09, darkBlue: 0.05
        ),
        forgeColor(
            lightRed: 0.98, lightGreen: 0.95, lightBlue: 0.90,
            darkRed: 0.09, darkGreen: 0.06, darkBlue: 0.05
        ),
        forgeColor(
            lightRed: 0.93, lightGreen: 0.89, lightBlue: 0.84,
            darkRed: 0.05, darkGreen: 0.03, darkBlue: 0.03
        ),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
let forgePanelFill = LinearGradient(
    colors: [
        forgeColor(
            lightRed: 0.99, lightGreen: 0.95, lightBlue: 0.91,
            darkRed: 0.21, darkGreen: 0.13, darkBlue: 0.09,
            alpha: 0.98
        ),
        forgeColor(
            lightRed: 0.96, lightGreen: 0.91, lightBlue: 0.86,
            darkRed: 0.14, darkGreen: 0.09, darkBlue: 0.07,
            alpha: 0.98
        ),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

struct EmberSpec: Identifiable {
    let id: Int
    let x: CGFloat
    let baseY: CGFloat
    let drift: CGFloat
    let size: CGFloat
    let speed: Double
    let phase: Double
    let opacity: Double
}

let forgeEmbers: [EmberSpec] = [
    .init(id: 0, x: 0.08, baseY: 0.92, drift: 0.26, size: 4, speed: 0.07, phase: 0.0, opacity: 0.34),
    .init(id: 1, x: 0.14, baseY: 0.88, drift: 0.30, size: 3, speed: 0.09, phase: 1.2, opacity: 0.28),
    .init(id: 2, x: 0.18, baseY: 0.95, drift: 0.22, size: 5, speed: 0.06, phase: 2.4, opacity: 0.32),
    .init(id: 3, x: 0.24, baseY: 0.90, drift: 0.24, size: 3, speed: 0.08, phase: 0.8, opacity: 0.26),
    .init(id: 4, x: 0.30, baseY: 0.94, drift: 0.20, size: 4, speed: 0.05, phase: 1.8, opacity: 0.30),
    .init(id: 5, x: 0.37, baseY: 0.89, drift: 0.28, size: 3, speed: 0.07, phase: 3.2, opacity: 0.22),
    .init(id: 6, x: 0.44, baseY: 0.93, drift: 0.18, size: 5, speed: 0.04, phase: 0.5, opacity: 0.18),
    .init(id: 7, x: 0.52, baseY: 0.91, drift: 0.23, size: 4, speed: 0.08, phase: 2.9, opacity: 0.24),
    .init(id: 8, x: 0.61, baseY: 0.96, drift: 0.17, size: 4, speed: 0.05, phase: 1.1, opacity: 0.20),
    .init(id: 9, x: 0.69, baseY: 0.90, drift: 0.25, size: 3, speed: 0.09, phase: 2.1, opacity: 0.24),
    .init(id: 10, x: 0.77, baseY: 0.93, drift: 0.19, size: 5, speed: 0.06, phase: 0.3, opacity: 0.28),
    .init(id: 11, x: 0.84, baseY: 0.88, drift: 0.32, size: 3, speed: 0.10, phase: 1.7, opacity: 0.22),
    .init(id: 12, x: 0.91, baseY: 0.95, drift: 0.21, size: 4, speed: 0.06, phase: 2.7, opacity: 0.24),
]

struct ForgeAmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let glowOpacity = colorScheme == .dark ? 0.28 : 0.14
            let emberOpacity = colorScheme == .dark ? 1.0 : 0.55

            ZStack {
                forgeBackdrop

                RadialGradient(
                    colors: [
                        forgeGlow.opacity(glowOpacity + 0.05 * sin(time * 1.6)),
                        appAccent.opacity(glowOpacity * 0.55),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 18,
                    endRadius: 240
                )
                .frame(width: 420, height: 320)
                .offset(x: 520, y: 320 + 10 * sin(time * 1.9))
                .blur(radius: 10)

                RadialGradient(
                    colors: [
                        appAccent.opacity((colorScheme == .dark ? 0.10 : 0.05) + 0.03 * sin(time * 2.8 + 0.8)),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 8,
                    endRadius: 180
                )
                .frame(width: 280, height: 220)
                .offset(x: -520, y: 360 + 8 * sin(time * 2.2))
                .blur(radius: 18)

                Canvas { context, size in
                    for ember in forgeEmbers {
                        let progress = (time * ember.speed + ember.phase).truncatingRemainder(dividingBy: 1.0)
                        let drift = CGFloat(progress) * ember.drift * size.height
                        let x = size.width * ember.x + CGFloat(sin(time * ember.speed * 9 + ember.phase)) * 14
                        let y = size.height * ember.baseY - drift
                        let pulse = 0.45 + 0.55 * ((sin(time * 5.5 + ember.phase) + 1) / 2)
                        let radius = ember.size * (0.9 + pulse * 0.45)
                        let rect = CGRect(x: x, y: y, width: radius, height: radius)
                        context.fill(Path(ellipseIn: rect), with: .color(forgeGlow.opacity(ember.opacity * pulse * emberOpacity)))
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }
}
