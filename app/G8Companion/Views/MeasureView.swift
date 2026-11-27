import SwiftUI

struct MeasureView: View {
    @Environment(AppModel.self) private var model
    @Environment(ControllerMonitor.self) private var monitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var seconds = 10.0
    @State private var rawSummary: TimingSummary?
    @State private var showFlash = false
    @State private var width = 0.0

    var body: some View {
        let accent = monitor.current.map { Identity(category: $0.productCategory, inputs: []).color } ?? Theme.graphite
        List {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 28) {
                    bigNumber("\(monitor.statesPerSecond)", "updates per second")
                    bigNumber(String(format: "%.1f", monitor.latencyMs), "ms inside the system")
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            } footer: {
                Text("Updates arrive when something changes, so keep a stick moving to see the full rate. The second number covers only the phone's own handling, from the report arriving to the app reading it; it leaves out the radio and the controller.")
            }

            Section {
                HStack(spacing: 20) {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: monitor.recording == nil)) { _ in
                        RecordButton(progress: progress, running: monitor.recording != nil, accent: accent) {
                            if monitor.recording == nil { start() } else { monitor.stopRecording() }
                        }
                    }
                    .disabled(monitor.current == nil)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(monitor.recording == nil ? "Record update timing" : "Keep moving a stick in circles")
                            .font(.headline)
                        Picker("Length", selection: $seconds) {
                            Text("5 s").tag(5.0); Text("10 s").tag(10.0); Text("30 s").tag(30.0)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 280)
                        .disabled(monitor.recording != nil)
                    }
                }
                .padding(.vertical, 6)
                if let t = monitor.lastTiming {
                    TimingSummaryView(title: "What games see", summary: t, accent: accent)
                        .transition(.opacity)
                }
                #if os(macOS)
                if let rawSummary { TimingSummaryView(title: "Every report from the controller", summary: rawSummary, accent: accent) }
                #endif
            } header: {
                Text("Time between updates")
            } footer: {
                Text("Over Bluetooth the phone or Mac decides how often the controller may send. A tight cluster of bars means a steady link.")
            }
            .onChange(of: monitor.recording == nil) { _, finished in if finished { finish() } }

            Section {
                ReleaseRow(title: "Left stick", tracker: monitor.leftRelease)
                ReleaseRow(title: "Right stick", tracker: monitor.rightRelease)
                HStack(spacing: 12) {
                    Button("Save result", systemImage: "square.and.arrow.down") { saveRelease() }
                        .buttonStyle(.borderedProminent)
                        .disabled(monitor.leftRelease.count + monitor.rightRelease.count == 0)
                    Button("Start over", systemImage: "arrow.counterclockwise") { monitor.resetReleases() }
                        .buttonStyle(.bordered)
                }
            } header: {
                Text("Stick return")
            } footer: {
                Text("Push a stick to its edge and let go, about 20 times per stick. Stick smoothing in the firmware shows up as a longer return to center. Compare builds with the same controller and the same phone.")
            }

            Section("Other tests") {
                Button { showFlash = true } label: {
                    Label { VStack(alignment: .leading) {
                        Text("Button to screen")
                        Text("Film the controller and screen in slow motion").font(.caption).foregroundStyle(.secondary)
                    } } icon: { Image(systemName: "camera.metering.spot") }
                }
                NavigationLink {
                    IdleTestView()
                } label: {
                    Label { VStack(alignment: .leading) {
                        Text("Idle power-off")
                        Text(model.idleTestStarted == nil ? "How long until the controller turns itself off" : "Running")
                            .font(.caption).foregroundStyle(model.idleTestStarted == nil ? Color.secondary : accent)
                    } } icon: { Image(systemName: "moon.zzz") }
                }
            }
        }
        // Keeps lines readable on the unfolded screen and the Mac.
        .contentMargins(.horizontal, max(0, (width - 720) / 2), for: .scrollContent)
        .onGeometryChange(for: Double.self) { $0.size.width } action: { width = $0 }
        .tint(accent)
        .animation(Theme.settle(reduceMotion), value: monitor.lastTiming)
        .navigationTitle("Measure")
        #if os(iOS)
        .fullScreenCover(isPresented: $showFlash) { FlashView() }
        #else
        .sheet(isPresented: $showFlash) { FlashView().frame(minWidth: 500, minHeight: 400) }
        #endif
    }

    private func saveRelease() {
        var log = model.newLog(.release, "Stick return")
        log.leftRelease = monitor.leftRelease
        log.rightRelease = monitor.rightRelease
        model.save(log)
        monitor.resetReleases()
    }

    private var progress: Double {
        guard let r = monitor.recording else { return 0 }
        return min(1, Date().timeIntervalSince(r.started) / r.seconds)
    }

    private func bigNumber(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.number()).contentTransition(.numericText())
            Text(label).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func start() {
        rawSummary = nil
        #if os(macOS)
        model.raw.start()
        #endif
        model.keepAwake(true)
        monitor.startRecording(seconds: seconds)
    }

    private func finish() {
        model.keepAwake(model.idleTestStarted != nil)
        #if os(macOS)
        rawSummary = model.raw.stop()
        #endif
        guard let t = monitor.lastTiming else { return }
        var log = model.newLog(.timing, "Time between updates")
        log.timing = t
        log.rawTiming = rawSummary
        model.save(log)
    }
}

struct ReleaseRow: View {
    let title: String
    let tracker: StickReleaseTracker

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            if let m = tracker.medianMs {
                Text(String(format: "%.0f ms", m)).font(Theme.number(.title3)).contentTransition(.numericText())
                Text("typical, \(tracker.count) releases").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("not measured yet").foregroundStyle(.secondary)
            }
        }
    }
}

/// A round record button that turns into a progress ring while recording.
struct RecordButton: View {
    let progress: Double
    let running: Bool
    let accent: Color
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(Theme.idle, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: running ? progress : 0)
                    .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 0.1), value: progress)
                RoundedRectangle(cornerRadius: running ? 6 : 22, style: .continuous)
                    .fill(enabled ? accent : Theme.graphite.opacity(0.5))
                    .frame(width: running ? 22 : 44, height: running ? 22 : 44)
                    .animation(Theme.settle(reduceMotion), value: running)
            }
            .frame(width: 64, height: 64)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(running ? "Stop recording" : "Start recording")
    }
}

struct TimingSummaryView: View {
    let title: String
    let summary: TimingSummary
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.heading(.headline))
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                stat(String(format: "%.1f", summary.medianMs), "typical gap, ms")
                stat(String(format: "%.1f", summary.p99Ms), "99% under, ms")
                stat(String(format: "%.0f", summary.maxMs), "longest, ms")
            }
            Histogram(summary: summary, accent: accent).frame(height: 84)
            Text("\(summary.events) updates in \(String(format: "%.1f", summary.seconds)) s, \(String(format: "%.0f", summary.perSecond)) per second")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func stat(_ v: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(Theme.number(.title2))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct Histogram: View {
    let summary: TimingSummary
    let accent: Color
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let top = max(1, summary.histogram.max() ?? 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(summary.histogram.enumerated()), id: \.offset) { i, n in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(n == top ? accent : accent.opacity(0.45))
                        .frame(height: max(2, 58 * CGFloat(n) / CGFloat(top) * (grown ? 1 : 0.02)))
                        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.75).delay(Double(i) * 0.03), value: grown)
                    Text(i == summary.histogram.count - 1 ? "\(Int(Double(i) * summary.bucketMs))+" : "\(Int(Double(i) * summary.bucketMs))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { grown = true }
        .accessibilityLabel("Histogram of gaps in milliseconds")
    }
}

struct IdleTestView: View {
    @Environment(AppModel.self) private var model
    @Environment(ControllerMonitor.self) private var monitor

    var body: some View {
        List {
            Section {
                if let started = model.idleTestStarted {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(monitor.lastInput.map { AppModel.minutes(Date().timeIntervalSince($0)) } ?? "0 s")
                                .font(Theme.number())
                            Text("since the last input").font(.footnote).foregroundStyle(.secondary)
                            Text("Test running for \(AppModel.minutes(Date().timeIntervalSince(started)))")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Button("Stop test", role: .cancel) { model.stopIdleTest() }
                } else {
                    Button("Start test", systemImage: "play.fill") { model.startIdleTest() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(monitor.current == nil)
                }
                if let r = model.idleResult { Text(r).font(.headline) }
            } footer: {
                Text("Start the test, put the controller down and leave this screen open. The screen stays on, and the app records how long after the last input the controller turned off. The result is saved to Logs.")
            }
        }
        .navigationTitle("Idle power-off")
    }
}

/// Full screen that flashes white when any button goes down, for slow-motion video timing.
struct FlashView: View {
    @Environment(ControllerMonitor.self) private var monitor
    @Environment(\.dismiss) private var dismiss
    @State private var lit = false
    @State private var lastName = ""
    @State private var count = 0
    @State private var flash = 0

    var body: some View {
        ZStack {
            (lit ? Color.white : Color.black).ignoresSafeArea()
            VStack(spacing: 12) {
                Text(lit ? lastName : "Press any button")
                    .font(Theme.heading(.largeTitle))
                    .foregroundStyle(lit ? .black : .white)
                Text("\(count) presses").font(.callout.monospacedDigit()).foregroundStyle(.gray)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent).tint(.gray)
                    .padding(.top, 30)
            }
        }
        .onAppear {
            monitor.onPress = { name, _ in
                lastName = shortName(name)
                count += 1
                lit = true   // no animation: the flash has to land on the next frame
                // A newer press keeps the screen lit for its own full 0.15 s.
                flash += 1
                let mine = flash
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { if flash == mine { lit = false } }
            }
        }
        .onDisappear { monitor.onPress = nil }
        // Keeps the status bar and home indicator out of the slow-motion video.
        .persistentSystemOverlays(.hidden)
        #if os(iOS)
        .statusBarHidden()
        #endif
    }
}
