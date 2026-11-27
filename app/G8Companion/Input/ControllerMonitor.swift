import Foundation
import GameController
import Observation

/// Input names the app knows how to place. Strings match Apple's GCInput names.
enum InputName {
    static let face = ["Button A", "Button B", "Button X", "Button Y"]
    static let shoulders = ["Left Shoulder", "Right Shoulder", "Left Trigger", "Right Trigger"]
    static let sticks = ["Left Thumbstick Button", "Right Thumbstick Button"]
    static let system = ["Button Menu", "Button Options", "Button Home", "Button Share"]
    static let paddles = ["Paddle 1", "Paddle 2", "Paddle 3", "Paddle 4"]
    static let dpad = ["Direction Pad Up", "Direction Pad Down", "Direction Pad Left", "Direction Pad Right"]
    static let ordered = face + shoulders + sticks + system + paddles + dpad
    static let known = Set(ordered)
}

/// One timing recording: the timestamps of every input state the framework delivered.
struct Recording {
    var started = Date()
    var seconds: Double
    var times: [Double] = []
    var latencies: [Double] = []
}

/// Watches game controllers through Apple's GameController framework, which is what games see.
@MainActor @Observable
final class ControllerMonitor {
    private(set) var controllers: [GCController] = []
    private(set) var current: GCController?

    // Live state of the current controller.
    private(set) var pressed: Set<String> = []
    private(set) var seen: Set<String> = []
    private(set) var reported: [String] = []        // inputs the controller's profile exposes, in display order
    private(set) var leftStick = SIMD2<Double>(0, 0)
    private(set) var rightStick = SIMD2<Double>(0, 0)
    private(set) var leftTrigger = 0.0
    private(set) var rightTrigger = 0.0
    /// Inputs that went down in the same input state. A paddle that also presses a stick click shows up here.
    private(set) var pressedTogether: [String] = []
    private(set) var statesPerSecond = 0
    /// Apple's lower bound on the time from the event to the app, averaged over the last second.
    private(set) var latencyMs = 0.0
    private(set) var lastInput: Date?

    var leftAnalyzer = StickAnalyzer()
    var rightAnalyzer = StickAnalyzer()
    var leftRelease = StickReleaseTracker()
    var rightRelease = StickReleaseTracker()
    var leftTriggerAnalyzer = TriggerAnalyzer()
    var rightTriggerAnalyzer = TriggerAnalyzer()

    /// Tab change asked for from the controller: hold View and press LB or RB. Counter makes each request distinct.
    private(set) var navigation = (step: 0, count: 0)

    private(set) var recording: Recording?
    private(set) var lastTiming: TimingSummary?
    /// Called on the main queue with the input name and its event timestamp when any input goes down.
    var onPress: ((String, Double) -> Void)?
    /// Called when a controller disconnects, with the time since its last input.
    var onDisconnect: ((GCController, TimeInterval?) -> Void)?

    private var recentTimes: [Double] = []
    private var recentLatencies: [Double] = []
    private var tokens: [NSObjectProtocol] = []

    init() {
        GCController.shouldMonitorBackgroundEvents = true
        let nc = NotificationCenter.default
        tokens.append(nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        tokens.append(nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let c = note.object as? GCController {
                    self.onDisconnect?(c, self.lastInput.map { Date().timeIntervalSince($0) })
                }
                self.refresh()
            }
        })
        refresh()
    }

    func refresh() {
        controllers = GCController.controllers()
        if let c = current, controllers.contains(where: { $0 === c }) { return }
        select(controllers.first)
    }

    func select(_ c: GCController?) {
        if let old = current { old.input.inputStateAvailableHandler = nil }
        current = c
        resetAll()
        guard let c else { reported = []; return }
        // Let the app receive Home and Share instead of the system acting on them.
        for name in ["Button Home", "Button Share", "Button Options"] {
            c.physicalInputProfile.buttons[name]?.preferredSystemGestureState = .disabled
        }
        let input = c.input
        input.queue = .main
        input.inputStateQueueDepth = 64
        input.inputStateAvailableHandler = { [weak self] live in
            MainActor.assumeIsolated {
                while let state = live.nextInputState() { self?.handle(state) }
            }
        }
        reported = Self.inputNames(of: c.physicalInputProfile)
    }

    func resetAll() {
        pressed = []; seen = []; pressedTogether = []
        resetSticks()
    }

    func resetReleases() { leftRelease = StickReleaseTracker(); rightRelease = StickReleaseTracker() }

    func resetSticks() {
        leftAnalyzer = StickAnalyzer(); rightAnalyzer = StickAnalyzer()
        leftTriggerAnalyzer = TriggerAnalyzer(); rightTriggerAnalyzer = TriggerAnalyzer()
    }

    func resetSeen() { seen = []; pressedTogether = [] }

    func startRecording(seconds: Double) {
        recording = Recording(seconds: seconds)
        lastTiming = nil
    }

    /// Ends the recording and returns its summary (nil when fewer than two states arrived).
    @discardableResult
    func stopRecording() -> (TimingSummary?, Recording?) {
        let r = recording
        recording = nil
        lastTiming = r.flatMap { TimingSummary.from(times: $0.times) }
        return (lastTiming, r)
    }

    // MARK: - Input handling

    private func handle(_ state: any GCDevicePhysicalInputState & GCDevicePhysicalInputStateDiff) {
        let t = state.lastEventTimestamp
        lastInput = Date()
        if var r = recording {
            r.times.append(t)
            r.latencies.append(state.lastEventLatency)
            recording = r
            if Date().timeIntervalSince(r.started) >= r.seconds { stopRecording() }
        }
        recentTimes.append(t)
        recentLatencies.append(state.lastEventLatency)
        while let first = recentTimes.first, t - first > 1 {
            recentTimes.removeFirst(); recentLatencies.removeFirst()
        }
        statesPerSecond = recentTimes.count
        latencyMs = recentLatencies.isEmpty ? 0 : recentLatencies.reduce(0, +) / Double(recentLatencies.count) * 1000

        var now = Set<String>()
        for button in state.buttons {
            let name = Self.name(of: button)
            let value = Double(button.pressedInput.value)
            if button.pressedInput.isPressed { now.insert(name) }
            if name == "Left Trigger" { leftTrigger = value; leftTriggerAnalyzer.add(value) }
            if name == "Right Trigger" { rightTrigger = value; rightTriggerAnalyzer.add(value) }
        }
        for pad in state.dpads {
            let name = Self.name(of: pad)
            let v = pad.xyAxes.value
            let p = SIMD2(Double(v.x), Double(v.y))
            switch name {
            case "Left Thumbstick":
                leftStick = p; leftAnalyzer.add(x: p.x, y: p.y)
                leftRelease.add(distance: (p.x * p.x + p.y * p.y).squareRoot(), at: t)
            case "Right Thumbstick":
                rightStick = p; rightAnalyzer.add(x: p.x, y: p.y)
                rightRelease.add(distance: (p.x * p.x + p.y * p.y).squareRoot(), at: t)
            case "Direction Pad":
                if pad.up.isPressed { now.insert("Direction Pad Up") }
                if pad.down.isPressed { now.insert("Direction Pad Down") }
                if pad.left.isPressed { now.insert("Direction Pad Left") }
                if pad.right.isPressed { now.insert("Direction Pad Right") }
            default: break
            }
        }
        let wentDown = now.subtracting(pressed)
        if wentDown.count >= 2 {
            pressedTogether.insert(wentDown.sorted().joined(separator: " + "), at: 0)
            if pressedTogether.count > 20 { pressedTogether.removeLast() }
        }
        if pressed.contains("Button Options") {
            if wentDown.contains("Left Shoulder") { navigation = (-1, navigation.count + 1) }
            if wentDown.contains("Right Shoulder") { navigation = (1, navigation.count + 1) }
        }
        for name in wentDown { onPress?(name, t) }
        if now != pressed { pressed = now }
        if !wentDown.isEmpty { seen.formUnion(wentDown) }
    }

    // MARK: - Names

    static func name(of element: any GCPhysicalInputElement) -> String {
        let aliases = element.aliases
        if let known = aliases.first(where: { InputName.known.contains($0) }) { return known }
        for special in ["Left Thumbstick", "Right Thumbstick", "Direction Pad"] where aliases.contains(special) { return special }
        return element.localizedName ?? aliases.sorted().first ?? "?"
    }

    /// Inputs the controller exposes. Read from the classic profile, which lists every element for every
    /// controller type; the newer live input can come back empty for some devices.
    static func inputNames(of profile: GCPhysicalInputProfile) -> [String] {
        var names = Set<String>()
        for (key, _) in profile.buttons {
            // The profile also lists each stick and the D-pad as four direction buttons; those are not separate inputs.
            if InputName.known.contains(key) || !(key.contains("Thumbstick") || key.contains("Direction Pad")) { names.insert(key) }
        }
        if profile.dpads[GCInputDirectionPad] != nil { names.formUnion(InputName.dpad) }
        let ordered = InputName.ordered.filter { names.contains($0) }
        return ordered + names.subtracting(InputName.known).sorted()
    }

    // MARK: - Description

    func info(_ c: GCController) -> ControllerInfo {
        var percent: Int?
        var stateText: String?
        if let b = c.battery {
            percent = Int((b.batteryLevel * 100).rounded())
            switch b.batteryState {
            case .charging: stateText = "charging"
            case .discharging: stateText = "on battery"
            case .full: stateText = "full"
            default: stateText = nil
            }
        }
        return ControllerInfo(name: c.vendorName ?? "Controller", category: c.productCategory,
                              batteryPercent: percent, batteryState: stateText, inputNames: reported)
    }
}
