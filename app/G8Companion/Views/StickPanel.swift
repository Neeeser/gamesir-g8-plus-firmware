import SwiftUI

/// One stick: its live position, the farthest point reached in each direction, and its numbers.
struct StickPanel: View {
    let title: String
    let position: SIMD2<Double>
    let analyzer: StickAnalyzer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.heading(.subheadline))
            Canvas { ctx, size in
                let side = min(size.width, size.height)
                let r = side / 2 - 6
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let disk = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                ctx.fill(disk, with: .color(Theme.idle))
                ctx.stroke(disk, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
                ctx.stroke(Path { p in p.move(to: CGPoint(x: c.x - r, y: c.y)); p.addLine(to: CGPoint(x: c.x + r, y: c.y))
                                      p.move(to: CGPoint(x: c.x, y: c.y - r)); p.addLine(to: CGPoint(x: c.x, y: c.y + r)) },
                           with: .color(.secondary.opacity(0.4)), lineWidth: 0.5)
                // Reach: farthest point seen in each sector.
                var reach = Path()
                for i in 0..<StickAnalyzer.sectors {
                    let a = (Double(i) + 0.5) / Double(StickAnalyzer.sectors) * 2 * .pi
                    let d = analyzer.reach[i] * r
                    let pt = CGPoint(x: c.x + cos(a) * d, y: c.y - sin(a) * d)
                    if i == 0 { reach.move(to: pt) } else { reach.addLine(to: pt) }
                }
                reach.closeSubpath()
                ctx.fill(reach, with: .style(TintShapeStyle().opacity(0.15)))
                ctx.stroke(reach, with: .style(TintShapeStyle().opacity(0.8)), lineWidth: 1.5)
                let dot = CGPoint(x: c.x + position.x * r, y: c.y - position.y * r)
                ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 7, y: dot.y - 7, width: 14, height: 14)), with: .style(TintShapeStyle()))
            }
            .frame(minWidth: 120, maxWidth: 220, minHeight: 120, maxHeight: 220)
            .aspectRatio(1, contentMode: .fit)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                row("At", String(format: "%+.2f, %+.2f", position.x, position.y))
                let s = analyzer.spread
                row("Noise", String(format: "%.3f, %.3f", s.x, s.y))
                row("Smallest", analyzer.smallestNonzero.map { String(format: "%.3f", $0) } ?? "-")
                row("Reach", analyzer.sectorsVisited < 30 ? "-" : String(format: "%.0f%%", analyzer.averageReach * 100))
            }
            .font(.caption.monospacedDigit())
            if analyzer.sectorsVisited < 30 {
                Text("Roll the stick around its edge").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow { Text(k).foregroundStyle(.secondary); Text(v) }
    }
}
