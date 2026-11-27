import SwiftUI

/// A live drawing of the GameSir G8 Plus (Bluetooth) seen from the front: two Xbox-style grips with
/// handles, the phone deck between them, bumpers with the triggers behind them, and the two rear
/// buttons peeking out under the handles. Positions are traced from GameSir's manual drawing.
struct ControllerDiagram: View {
    @Environment(ControllerMonitor.self) private var monitor
    let accent: Color

    var body: some View {
        ControllerDrawing(state: DiagramState(
            pressed: monitor.pressed, seen: monitor.seen, reported: Set(monitor.reported),
            leftStick: monitor.leftStick, rightStick: monitor.rightStick,
            leftTrigger: monitor.leftTrigger, rightTrigger: monitor.rightTrigger,
            connected: monitor.current != nil), accent: accent)
    }
}

// MARK: - Drawing (no dependency on the monitor, so previews can feed it any state)

struct DiagramState {
    var pressed: Set<String> = []
    var seen: Set<String> = []
    var reported: Set<String> = []
    var leftStick = SIMD2<Double>(0, 0)
    var rightStick = SIMD2<Double>(0, 0)
    var leftTrigger = 0.0
    var rightTrigger = 0.0
    var connected = false
}

/// Layout in design units. The left grip is drawn in its own coordinates; the right grip is its mirror
/// image, x' = width - x. The deck is the telescopic phone holder; its width is a free choice, since the
/// real one stretches to fit the phone.
enum G8Layout {
    static let gripReach = 93.0          // grip outer edge (x = 0) to where the deck starts
    static let deck = 140.0              // deck width between the grips
    static let width = 2 * gripReach + deck   // 326
    static let height = 214.0
    static func mirror(_ x: Double) -> Double { width - x }

    // Deck (phone holder)
    static let deckRect = CGRect(x: gripReach, y: 27, width: deck, height: 135)
    static let railInset = 10.0          // the telescopic rails at each end of the deck

    // Left grip; right grip uses mirror(x)
    static let triggerRect = CGRect(x: 40, y: 7, width: 40, height: 15)   // LT; the bumper covers it below y = 18
    static let bumperTop = 18.0
    static let view = CGPoint(x: 82, y: 48), smallButtonR = 5.5            // View (-) / Menu (+)
    static let leftStick = CGPoint(x: 58, y: 70)
    static let stickWellR = 19.0, stickCapR = 12.0, stickTravel = 6.0
    static let dpad = CGPoint(x: 65, y: 122)
    static let dpadHalfSpan = 21.0, dpadArm = 16.0
    static let capturePill = CGRect(x: 52, y: 153, width: 27, height: 12)  // capture dot + M button
    static let capture = CGPoint(x: 59, y: 159), captureR = 4.5
    static let mButton = CGPoint(x: 71.5, y: 159)
    static let backTab = CGRect(x: 19, y: 202, width: 24, height: 11)     // rear button, peeks under the handle

    // Right grip, already mirrored
    static let abxy = CGPoint(x: mirror(58), y: 72), faceOffset = 17.0, faceR = 8.0
    static let rightStick = CGPoint(x: mirror(65), y: 124)
    static let home = CGPoint(x: mirror(65), y: 161), homeR = 7.5

    /// Which Apple input each rear button arrives as. With patches/bt-xbox-elite-paddles.txt the paddle
    /// byte is (right << 1) | left, so the left rear button is Paddle 1. Not yet checked on hardware.
    static let leftBack = "Paddle 1", rightBack = "Paddle 2"
}

/// Outline of the left grip in design units: top edge, outer edge, handle lobe, then back up to the deck.
struct GripShape: Shape {
    var mirrored = false
    func path(in rect: CGRect) -> Path {
        let s = rect.width / G8Layout.width
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: (mirrored ? G8Layout.mirror(x) : x) * s, y: y * s)
        }
        var path = Path()
        path.move(to: p(100, 27))
        path.addLine(to: p(40, 31))
        path.addCurve(to: p(22, 46), control1: p(32, 31.5), control2: p(26, 36))
        path.addCurve(to: p(3, 125), control1: p(14, 66), control2: p(7, 95))
        path.addCurve(to: p(7, 187), control1: p(0, 150), control2: p(1, 172))
        path.addCurve(to: p(33, 204), control1: p(12, 199), control2: p(22, 205))
        path.addCurve(to: p(66, 180), control1: p(44, 203), control2: p(54, 192))
        path.addCurve(to: p(100, 162), control1: p(76, 170), control2: p(86, 163))
        path.closeSubpath()
        return path
    }
}

/// The bumper as seen from the front: a raised wedge sitting on the grip's top edge.
struct BumperShape: Shape {
    var mirrored = false
    func path(in rect: CGRect) -> Path {
        let s = rect.width / G8Layout.width
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: (mirrored ? G8Layout.mirror(x) : x) * s, y: y * s)
        }
        var path = Path()
        path.move(to: p(34, 33))
        path.addLine(to: p(88, 27.5))
        path.addCurve(to: p(72, 18), control1: p(84, 21), control2: p(79, 18))
        path.addLine(to: p(50, 18.5))
        path.addCurve(to: p(34, 33), control1: p(42, 19), control2: p(37, 24))
        path.closeSubpath()
        return path
    }
}

/// The D-pad as one plus shape.
struct DPadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let h = min(rect.width, rect.height) / 2, t = h * (G8Layout.dpadArm / 2) / G8Layout.dpadHalfSpan
        let c = CGPoint(x: rect.midX, y: rect.midY), r = t * 0.5
        var path = Path()
        path.addRoundedRect(in: CGRect(x: c.x - t, y: c.y - h, width: 2 * t, height: 2 * h), cornerSize: CGSize(width: r, height: r))
        path.addRoundedRect(in: CGRect(x: c.x - h, y: c.y - t, width: 2 * h, height: 2 * t), cornerSize: CGSize(width: r, height: r))
        return path
    }
}

struct ControllerDrawing: View {
    let state: DiagramState
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias L = G8Layout

    var body: some View {
        let names = state.reported
        let seenCount = names.filter { state.seen.contains($0) }.count
        GeometryReader { geo in
            let s = geo.size.width / L.width
            ZStack(alignment: .topLeading) {
                // Back to front: rear buttons and triggers sit behind the body.
                backTab(L.leftBack, label: "L4", mirrored: false, s: s)
                backTab(L.rightBack, label: "R4", mirrored: true, s: s)
                trigger("Left Trigger", value: state.leftTrigger, mirrored: false, s: s)
                trigger("Right Trigger", value: state.rightTrigger, mirrored: true, s: s)

                ForEach([false, true], id: \.self) { m in
                    GripShape(mirrored: m).fill(Theme.body)
                    GripShape(mirrored: m).stroke(Theme.edge, lineWidth: 1)
                }
                bumper("Left Shoulder", "LB", mirrored: false, s: s)
                bumper("Right Shoulder", "RB", mirrored: true, s: s)
                deck(seen: seenCount, total: names.count, s: s)

                // Left grip
                stick("Left Thumbstick Button", position: state.leftStick, at: L.leftStick, s: s)
                dpad(s: s)
                small("Button Options", symbol: "minus", at: L.view, s: s)
                RoundedRectangle(cornerRadius: L.capturePill.height / 2 * s, style: .continuous)
                    .fill(Theme.well)
                    .frame(width: L.capturePill.width * s, height: L.capturePill.height * s)
                    .position(x: L.capturePill.midX * s, y: L.capturePill.midY * s)
                small("Button Share", symbol: nil, at: L.capture, r: L.captureR, s: s)
                Text("M").font(.system(size: 6 * s, weight: .heavy).width(.expanded))
                    .foregroundStyle(Theme.label.opacity(0.6))
                    .position(x: L.mButton.x * s, y: L.mButton.y * s)

                // Right grip
                face("Button Y", "Y", dx: 0, dy: -1, s: s)
                face("Button X", "X", dx: -1, dy: 0, s: s)
                face("Button B", "B", dx: 1, dy: 0, s: s)
                face("Button A", "A", dx: 0, dy: 1, s: s)
                stick("Right Thumbstick Button", position: state.rightStick, at: L.rightStick, s: s)
                small("Button Menu", symbol: "plus", at: CGPoint(x: L.mirror(L.view.x), y: L.view.y), s: s)
                home(s: s)
            }
        }
        .aspectRatio(L.width / L.height, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Controller, \(seenCount) of \(names.count) inputs seen")
    }

    // MARK: States

    private enum Look { case unreported, idle, seen, pressed }

    private func look(_ name: String) -> Look {
        if !state.reported.contains(name) { return .unreported }
        if state.pressed.contains(name) { return .pressed }
        return state.seen.contains(name) ? .seen : .idle
    }

    private func fill(_ look: Look) -> Color {
        switch look {
        case .unreported: .clear
        case .idle: Theme.control
        case .seen: Theme.control.mix(with: accent, by: 0.55)
        case .pressed: accent
        }
    }

    private func labelColor(_ look: Look) -> Color {
        look == .unreported ? Theme.label.opacity(0.3) : look == .pressed ? .white : Theme.label
    }

    /// Press lands on the next frame with no easing, since this is a latency tester; release springs back.
    private func pressMotion(_ pressed: Bool) -> Animation? {
        pressed || reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)
    }

    // MARK: Parts

    private func control<S: Shape>(_ shape: S, _ name: String, scale: Double = 0.9) -> some View {
        let lk = look(name)
        return shape.fill(fill(lk))
            .overlay(shape.stroke(Theme.label.opacity(lk == .unreported ? 0.3 : 0), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2])))
            .shadow(color: lk == .pressed ? accent.opacity(0.7) : .clear, radius: 5)
            .scaleEffect(lk == .pressed && !reduceMotion ? scale : 1)
            .animation(pressMotion(lk == .pressed), value: lk == .pressed)
    }

    private func small(_ name: String, symbol: String?, at c: CGPoint, r: Double = G8Layout.smallButtonR, s: Double) -> some View {
        control(Circle(), name)
            .overlay {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: r * 1.2 * s, weight: .heavy)).foregroundStyle(labelColor(look(name)))
                }
            }
            .frame(width: 2 * r * s, height: 2 * r * s)
            .position(x: c.x * s, y: c.y * s)
    }

    private func face(_ name: String, _ label: String, dx: Double, dy: Double, s: Double) -> some View {
        let r = L.faceR
        return control(Circle(), name)
            .overlay(Text(label).font(.system(size: 8 * s, weight: .bold).width(.expanded)).foregroundStyle(labelColor(look(name))))
            .frame(width: 2 * r * s, height: 2 * r * s)
            .position(x: (L.abxy.x + dx * L.faceOffset) * s, y: (L.abxy.y + dy * L.faceOffset) * s)
    }

    private func home(s: Double) -> some View {
        // The ring around Home is the controller's connection light, so it shows the mode color while connected.
        let side: Double = 2 * L.homeR * s
        let light: Color = state.connected ? accent : Theme.label.opacity(0.25)
        let glyph: Color = labelColor(look("Button Home"))
        return control(Circle(), "Button Home")
            .overlay(Circle().strokeBorder(light, lineWidth: 1.5 * s))
            .overlay(Image(systemName: "house.fill").font(.system(size: 6.5 * s, weight: .bold)).foregroundStyle(glyph))
            .frame(width: side, height: side)
            .position(x: L.home.x * s, y: L.home.y * s)
    }

    private func bumper(_ name: String, _ label: String, mirrored: Bool, s: Double) -> some View {
        let lk = look(name)
        let midX = mirrored ? L.mirror(61) : 61
        return BumperShape(mirrored: mirrored).fill(lk == .idle || lk == .unreported ? Theme.bumper : fill(lk))
            .overlay(Text(label).font(.system(size: 6.5 * s, weight: .heavy).width(.expanded))
                .foregroundStyle(labelColor(lk))
                .position(x: midX * s, y: 25 * s))
            .shadow(color: lk == .pressed ? accent.opacity(0.7) : .clear, radius: 5)
            .offset(y: lk == .pressed && !reduceMotion ? 1.5 * s : 0)
            .animation(pressMotion(lk == .pressed), value: lk == .pressed)
    }

    private func trigger(_ name: String, value: Double, mirrored: Bool, s: Double) -> some View {
        // Fills upward with the analog value; only the part above the bumper is visible.
        let lk = look(name)
        let r = L.triggerRect
        let x = mirrored ? L.mirror(r.maxX) : r.minX
        let visible = L.bumperTop - r.minY
        return ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(topLeadingRadius: 7.5 * s, topTrailingRadius: 7.5 * s, style: .continuous)
                .fill(lk == .seen || lk == .pressed ? Theme.control.mix(with: accent, by: 0.35) : Theme.bumper)
            Rectangle().fill(accent)
                .frame(height: (r.height - visible + visible * min(1, max(0, value))) * s)
                .opacity(value > 0.01 ? 1 : 0)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 7.5 * s, topTrailingRadius: 7.5 * s, style: .continuous))
        .frame(width: r.width * s, height: r.height * s)
        .position(x: (x + r.width / 2) * s, y: r.midY * s)
    }

    private func stick(_ click: String, position: SIMD2<Double>, at c: CGPoint, s: Double) -> some View {
        let lk = look(click)
        let down = lk == .pressed
        let travel: Double = L.stickTravel * s
        let capSide: Double = 2 * L.stickCapR * s
        let ring: Color = lk == .seen ? accent.opacity(0.8) : Theme.control
        let glow: Color = down ? accent.opacity(0.7) : Color.black.opacity(0.4)
        let cap = Circle()
            .fill(down ? accent : Theme.cap)
            .overlay(Circle().strokeBorder(Theme.edge, lineWidth: 1))
            .frame(width: capSide, height: capSide)
            .shadow(color: glow, radius: down ? 5 : 2, y: down ? 0 : 1)
            .scaleEffect(down && !reduceMotion ? 0.92 : 1)
            .offset(x: position.x * travel, y: -position.y * travel)
            .animation(pressMotion(down), value: down)
        return ZStack {
            Circle().fill(Theme.well)
            Circle().strokeBorder(ring, lineWidth: 1.5 * s)
            cap
        }
        .frame(width: 2 * L.stickWellR * s, height: 2 * L.stickWellR * s)
        .position(x: c.x * s, y: c.y * s)
    }

    private func dpad(s: Double) -> some View {
        let h = L.dpadHalfSpan, t = L.dpadArm / 2
        let arm = { (name: String, dx: Double, dy: Double) -> AnyView in
            let lk = self.look(name)
            let w = dx == 0 ? 2 * t : h - t, hh = dy == 0 ? 2 * t : h - t
            return AnyView(
                UnevenRoundedRectangle(
                    topLeadingRadius: (dy < 0 || dx < 0 ? 3.5 : 0) * s, bottomLeadingRadius: (dy > 0 || dx < 0 ? 3.5 : 0) * s,
                    bottomTrailingRadius: (dy > 0 || dx > 0 ? 3.5 : 0) * s, topTrailingRadius: (dy < 0 || dx > 0 ? 3.5 : 0) * s)
                .fill(lk == .idle ? .clear : self.fill(lk))
                .frame(width: w * s, height: hh * s)
                .offset(x: dx * (t + (h - t) / 2) * s, y: dy * (t + (h - t) / 2) * s)
                .shadow(color: lk == .pressed ? self.accent.opacity(0.7) : .clear, radius: 5))
        }
        return ZStack {
            DPadShape().fill(Theme.control)
            arm("Direction Pad Up", 0, -1)
            arm("Direction Pad Down", 0, 1)
            arm("Direction Pad Left", -1, 0)
            arm("Direction Pad Right", 1, 0)
        }
        .frame(width: 2 * h * s, height: 2 * h * s)
        .position(x: L.dpad.x * s, y: L.dpad.y * s)
    }

    private func backTab(_ name: String, label: String, mirrored: Bool, s: Double) -> some View {
        let lk = look(name)
        let r = L.backTab
        let x = mirrored ? L.mirror(r.maxX) : r.minX
        return Capsule()
            .fill(lk == .idle ? Theme.bumper : fill(lk))
            // Most of the tab sits on the page background, so the not-reported outline uses the page's own text color.
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(lk == .unreported ? 1 : 0), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2])))
            .overlay(alignment: .bottom) {
                Text(label).font(.system(size: 5.5 * s, weight: .heavy).width(.expanded))
                    .foregroundStyle(lk == .unreported ? Color.secondary : labelColor(lk))
                    .padding(.bottom, 1.2 * s)
            }
            .shadow(color: lk == .pressed ? accent.opacity(0.7) : .clear, radius: 5)
            .frame(width: r.width * s, height: r.height * s)
            .offset(y: lk == .pressed && !reduceMotion ? -1.5 * s : 0)
            .animation(pressMotion(lk == .pressed), value: lk == .pressed)
            .position(x: (x + r.width / 2) * s, y: r.midY * s)
    }

    private func deck(seen: Int, total: Int, s: Double) -> some View {
        let d = L.deckRect
        return ZStack {
            RoundedRectangle(cornerRadius: 4 * s, style: .continuous).fill(Theme.deck)
            RoundedRectangle(cornerRadius: 4 * s, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1)
            // The two telescopic rails.
            HStack {
                Rectangle().fill(Theme.edge).frame(width: 1)
                Spacer()
                Rectangle().fill(Theme.edge).frame(width: 1)
            }
            .padding(.horizontal, L.railInset * s)
            PhoneSlot(seen: seen, total: total, accent: accent, connected: state.connected)
        }
        .frame(width: d.width * s, height: d.height * s)
        .position(x: d.midX * s, y: d.midY * s)
    }
}

/// The middle of the drawing, where the phone sits: shows how far the button check has got.
private struct PhoneSlot: View {
    let seen: Int
    let total: Int
    let accent: Color
    let connected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let done = connected && total > 0 && seen == total
        VStack(spacing: 2) {
            if !connected {
                Image(systemName: "gamecontroller").font(.title2)
                Text("Not connected").font(.caption2.weight(.medium))
            } else if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(accent)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                Text("All inputs work").font(.caption2.weight(.semibold))
            } else {
                Text("\(seen)")
                    .font(Theme.number(.title))
                    .contentTransition(.numericText(value: Double(seen)))
                Text("of \(total) seen").font(.caption2).foregroundStyle(Theme.label.opacity(0.7))
            }
        }
        .foregroundStyle(Theme.label)
        .animation(Theme.settle(reduceMotion), value: seen)
        .animation(Theme.settle(reduceMotion), value: done)
        .sensoryFeedback(.success, trigger: done) { _, new in new }
    }
}
