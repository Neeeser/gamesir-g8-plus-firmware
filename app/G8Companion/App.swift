import GameController
import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct G8CompanionApp: App {
    @State private var model = AppModel()

    init() {
        #if os(iOS)
        // Titles in the same expanded face as the headings inside the screens.
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: UIFont.systemFont(ofSize: 34, weight: .semibold, width: .expanded)]
        UINavigationBar.appearance().titleTextAttributes = [.font: UIFont.systemFont(ofSize: 17, weight: .semibold, width: .expanded)]
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.monitor)
        }
    }
}

/// App-wide state: the controller monitor, saved logs and the firmware label.
@MainActor @Observable
final class AppModel {
    let monitor = ControllerMonitor()
    let rumble = Rumble()
    #if os(macOS)
    let raw = RawReports()
    #endif
    let store = LogStore(folder: LogStore.defaultFolder())
    private(set) var logs: [(RunLog, URL)] = []
    private(set) var lastError: String?

    /// The firmware the person says is on the controller. Saved with every log.
    var firmware: String = UserDefaults.standard.string(forKey: "firmware") ?? "" {
        didSet { UserDefaults.standard.set(firmware, forKey: "firmware") }
    }

    /// When the idle power-off test started; nil when it is not running.
    private(set) var idleTestStarted: Date?
    private(set) var idleResult: String?

    init() {
        reloadLogs()
        monitor.onDisconnect = { [weak self] c, sinceInput in self?.controllerLeft(c, sinceInput: sinceInput) }
    }

    func startIdleTest() {
        idleTestStarted = Date()
        idleResult = nil
        keepAwake(true)
    }

    func stopIdleTest() {
        idleTestStarted = nil
        keepAwake(false)
    }

    private func controllerLeft(_ c: GCController, sinceInput: TimeInterval?) {
        guard let started = idleTestStarted else { return }
        let idle = sinceInput ?? Date().timeIntervalSince(started)
        var log = newLog(.idle, "Idle power-off")
        log.controller = monitor.info(c)
        log.notes = [String(format: "Disconnected %.0f s (%@) after the last input.", idle, Self.minutes(idle)),
                     String(format: "Test started %.0f s before the disconnect.", Date().timeIntervalSince(started))]
        save(log)
        idleResult = "The controller disconnected \(Self.minutes(idle)) after the last input."
        stopIdleTest()
    }

    static func minutes(_ s: TimeInterval) -> String {
        let m = Int(s) / 60, sec = Int(s) % 60
        return m > 0 ? "\(m) min \(sec) s" : "\(sec) s"
    }

    /// Keeps the phone from locking during long tests, since a locked phone stops the app.
    func keepAwake(_ on: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = on
        #endif
    }

    func newLog(_ kind: RunLog.Kind, _ title: String) -> RunLog {
        RunLog(kind: kind, title: title, firmware: firmware, device: DeviceInfo.model, system: DeviceInfo.system,
               controller: monitor.current.map { monitor.info($0) })
    }

    func save(_ log: RunLog) {
        do { try store.save(log); lastError = nil } catch { lastError = "Could not save the log: \(error.localizedDescription)" }
        reloadLogs()
    }

    func delete(_ url: URL) {
        try? store.delete(url)
        reloadLogs()
    }

    func reloadLogs() { logs = store.load() }
}

struct RootView: View {
    enum Screen: Int, CaseIterable { case test, measure, logs }
    @Environment(ControllerMonitor.self) private var monitor
    @State private var screen = Screen.test

    var body: some View {
        TabView(selection: $screen) {
            Tab("Test", systemImage: "gamecontroller.fill", value: Screen.test) { NavigationStack { TestView() } }
            Tab("Measure", systemImage: "waveform.path.ecg", value: Screen.measure) { NavigationStack { MeasureView() } }
            Tab("Logs", systemImage: "list.bullet.rectangle", value: Screen.logs) { NavigationStack { LogsView() } }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onChange(of: monitor.navigation.count) {
            let all = Screen.allCases
            let next = (screen.rawValue + monitor.navigation.step + all.count) % all.count
            screen = all[next]
        }
    }
}

/// Shown on every test screen when no controller is connected.
struct NoControllerNote: View {
    @Environment(ControllerMonitor.self) private var monitor
    var body: some View {
        if monitor.current == nil {
            Label("No controller connected. Pair it in Bluetooth settings or plug it in.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}
