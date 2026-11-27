import SwiftUI

/// Everything the controller sends, on one screen: buttons, sticks and triggers.
struct TestView: View {
    @Environment(AppModel.self) private var model
    @Environment(ControllerMonitor.self) private var monitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showDetails = false
    @State private var width = 0.0
    @State private var savedNote: String?

    var body: some View {
        let identity = Identity(category: monitor.current?.productCategory ?? "", inputs: monitor.reported)
        let accent = monitor.current == nil ? Theme.graphite : identity.color
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StatusBar(accent: accent) { showDetails = true }
                if width >= 760 {
                    // Unfolded or landscape: drawing on the left, live numbers beside it, so nothing sits below the fold.
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            ControllerDiagram(accent: accent)
                            hint
                            if !monitor.pressedTogether.isEmpty { togetherNote }
                        }
                        .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 16) { sticks }.frame(width: 340)
                    }
                } else {
                    ControllerDiagram(accent: accent)
                    hint
                    if !monitor.pressedTogether.isEmpty { togetherNote }
                    sticks
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
            .animation(Theme.settle(reduceMotion), value: monitor.pressedTogether)
        }
        .safeAreaInset(edge: .bottom) {
            actions.padding(.horizontal).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
        }
        .onGeometryChange(for: Double.self) { $0.size.width } action: { width = $0 }
        .tint(accent)
        .navigationTitle("Test")
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $showDetails) {
            NavigationStack { ControllerDetails().toolbar { Button("Done") { showDetails = false } } }
                .tint(accent)
                #if os(macOS)
                .frame(minWidth: 420, minHeight: 520)
                #endif
        }
    }

    @ViewBuilder private var hint: some View {
        if monitor.current != nil {
            Label("Hold View (−) and press LB or RB to switch tabs", systemImage: "gamecontroller")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var togetherNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("One press sent two inputs", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.orange)
            Text("A button is copied onto another, such as a paddle that also clicks a stick.")
                .font(.footnote).foregroundStyle(.secondary)
            ForEach(Array(monitor.pressedTogether.prefix(4).enumerated()), id: \.offset) { _, s in
                Text(shortName(s)).font(.callout.weight(.medium))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder private var sticks: some View {
        HStack(alignment: .top, spacing: 16) { stickPanels }
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            TriggerLine(title: "Left trigger", value: monitor.leftTrigger, analyzer: monitor.leftTriggerAnalyzer)
            TriggerLine(title: "Right trigger", value: monitor.rightTrigger, analyzer: monitor.rightTriggerAnalyzer)
        }
        if monitor.leftTriggerAnalyzer.steps <= 1 && monitor.rightTriggerAnalyzer.steps <= 1 {
            Text("Pull each trigger slowly to measure its range.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var stickPanels: some View {
        StickPanel(title: "Left stick", position: monitor.leftStick, analyzer: monitor.leftAnalyzer)
        StickPanel(title: "Right stick", position: monitor.rightStick, analyzer: monitor.rightAnalyzer)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button("Save result", systemImage: "square.and.arrow.down") { save() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(monitor.current == nil)
                Button("Start over", systemImage: "arrow.counterclockwise") {
                    withAnimation(Theme.settle(reduceMotion)) { monitor.resetAll() }
                    savedNote = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            if let savedNote { Text(savedNote).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private func save() {
        var log = model.newLog(.buttons, "Controller check")
        let missing = monitor.reported.filter { !monitor.seen.contains($0) }
        log.buttonsSeen = monitor.reported.filter { monitor.seen.contains($0) }
        log.buttonsMissing = missing
        log.pressedTogether = monitor.pressedTogether
        log.leftStick = monitor.leftAnalyzer
        log.rightStick = monitor.rightAnalyzer
        log.leftTrigger = monitor.leftTriggerAnalyzer
        log.rightTrigger = monitor.rightTriggerAnalyzer
        model.save(log)
        savedNote = missing.isEmpty ? "Saved. Every input worked." : "Saved. Not pressed yet: \(missing.map(shortName).joined(separator: ", "))."
    }
}

/// Top line: which controller, in which mode, its battery and the firmware label. Opens the details sheet.
struct StatusBar: View {
    @Environment(AppModel.self) private var model
    @Environment(ControllerMonitor.self) private var monitor
    let accent: Color
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Circle().fill(accent).frame(width: 8, height: 8)
                    .shadow(color: accent.opacity(0.8), radius: monitor.current == nil ? 0 : 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(monitor.current?.vendorName ?? "No controller").font(Theme.heading(.subheadline)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let b = monitor.current?.battery, b.batteryLevel > 0 {
                    Label("\(Int((b.batteryLevel * 100).rounded()))%", systemImage: b.batteryState == .charging ? "battery.100.bolt" : "battery.75")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private var subtitle: String {
        guard let c = monitor.current else { return "Pair it in Bluetooth settings or plug it in" }
        let fw = model.firmware.isEmpty ? "firmware not set" : "firmware \(model.firmware)"
        return "\(c.productCategory), \(fw)"
    }
}

struct TriggerLine: View {
    let title: String
    let value: Double
    let analyzer: TriggerAnalyzer

    var body: some View {
        GridRow {
            Text(title).font(.subheadline.weight(.medium))
            Gauge(value: value) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
            Text(String(format: "%.2f", value)).font(.callout.monospacedDigit()).frame(minWidth: 40, alignment: .trailing)
        }
        GridRow {
            Text(analyzer.steps <= 1 ? " "
                 : String(format: "%.2f to %.2f, %d steps", analyzer.minValue, analyzer.maxValue, analyzer.steps))
                .font(.caption).foregroundStyle(.secondary)
                .gridCellColumns(3)
        }
    }
}
