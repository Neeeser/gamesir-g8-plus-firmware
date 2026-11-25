// Shows how Apple's GameController framework classifies each connected
// controller (the same framework iOS games use for button glyphs), and
// counts raw HID input reports per second for every gamepad on USB or
// Bluetooth. Run: swift tools/controller-probe.swift [seconds]
import Foundation
import GameController
import IOKit.hid

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "") ?? 6

// Report counting goes through IOHIDManager so the number reflects what the
// controller sends, not how often a game would see a value change.
final class ReportCounter {
    var counts: [String: Int] = [:]
    var sizes: [String: Set<Int>] = [:]
    var ids: [String: [UInt8: Int]] = [:]
}
let counter = ReportCounter()
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matches: [[String: Int]] = [
    [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad],
    [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick],
    [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_MultiAxisController],
]
IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
var buffers: [UnsafeMutablePointer<UInt8>] = []

func prop(_ d: IOHIDDevice, _ key: String) -> Any? { IOHIDDeviceGetProperty(d, key as CFString) }
func label(_ d: IOHIDDevice) -> String {
    let name = prop(d, kIOHIDProductKey) as? String ?? "?"
    let vid = prop(d, kIOHIDVendorIDKey) as? Int ?? 0
    let pid = prop(d, kIOHIDProductIDKey) as? Int ?? 0
    let transport = prop(d, kIOHIDTransportKey) as? String ?? "?"
    return String(format: "%@ [%04x:%04x %@]", name, vid, pid, transport)
}

let ctx = Unmanaged.passUnretained(counter).toOpaque()
IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
    let c = Unmanaged<ReportCounter>.fromOpaque(ctx!).takeUnretainedValue()
    let key = label(device)
    c.counts[key] = c.counts[key] ?? 0
    let size = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? 64
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: max(size, 64))
    buffers.append(buf)
    IOHIDDeviceRegisterInputReportCallback(device, buf, max(size, 64), { ctx, _, sender, _, reportID, _, length in
        let c = Unmanaged<ReportCounter>.fromOpaque(ctx!).takeUnretainedValue()
        let d = Unmanaged<IOHIDDevice>.fromOpaque(sender!).takeUnretainedValue()
        let key = label(d)
        c.counts[key, default: 0] += 1
        c.sizes[key, default: []].insert(length)
        c.ids[key, default: [:]][UInt8(truncatingIfNeeded: reportID), default: 0] += 1
    }, ctx)
}, ctx)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

GCController.shouldMonitorBackgroundEvents = true

func describe(_ c: GCController) {
    print("== GameController framework view ==")
    print("vendorName:      \(c.vendorName ?? "nil")")
    print("productCategory: \(c.productCategory)")
    print("isAttachedToDevice: \(c.isAttachedToDevice)")
    print("extendedGamepad: \(c.extendedGamepad != nil)  microGamepad: \(c.microGamepad != nil)")
    print("motion: \(c.motion.map { "yes (gravity+userAccel: \($0.hasGravityAndUserAcceleration), attitude: \($0.hasAttitude), rotationRate: \($0.hasRotationRate))" } ?? "no")")
    print("haptics: \(c.haptics.map { "localities \($0.supportedLocalities.map { $0.rawValue }.sorted())" } ?? "no")")
    print("battery: \(c.battery.map { "\(Int($0.batteryLevel * 100))% state \($0.batteryState.rawValue)" } ?? "no")")
    print("light: \(c.light != nil)")
    if let g = c.extendedGamepad {
        // sfSymbolsName is the glyph Apple hands a game for each button.
        let named: [(String, GCControllerElement?)] = [
            ("buttonA (bottom)", g.buttonA), ("buttonB (right)", g.buttonB),
            ("buttonX (left)", g.buttonX), ("buttonY (top)", g.buttonY),
            ("leftShoulder", g.leftShoulder), ("rightShoulder", g.rightShoulder),
            ("leftTrigger", g.leftTrigger), ("rightTrigger", g.rightTrigger),
            ("buttonMenu", g.buttonMenu), ("buttonOptions", g.buttonOptions),
            ("buttonHome", g.buttonHome),
            ("leftThumbstickButton", g.leftThumbstickButton), ("rightThumbstickButton", g.rightThumbstickButton),
        ]
        print("-- extendedGamepad buttons: glyph | localized name | analog --")
        for (n, e) in named {
            guard let e else { print("  \(n): missing"); continue }
            print("  \(n): \(e.sfSymbolsName ?? "-") | \(e.localizedName ?? "-") | analog=\(e.isAnalog)")
        }
    }
    let profile = c.physicalInputProfile
    print("-- every element the framework exposes (\(profile.elements.count)) --")
    for key in profile.elements.keys.sorted() {
        let e = profile.elements[key]!
        print("  \(key): glyph=\(e.sfSymbolsName ?? "-") analog=\(e.isAnalog)")
    }
}

var seen = Set<ObjectIdentifier>()
NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { n in
    if let c = n.object as? GCController, seen.insert(ObjectIdentifier(c)).inserted { describe(c) }
}
GCController.startWirelessControllerDiscovery {}

let start = Date()
RunLoop.main.run(until: start.addingTimeInterval(seconds))
for c in GCController.controllers() where seen.insert(ObjectIdentifier(c)).inserted { describe(c) }
let elapsed = Date().timeIntervalSince(start)
print("== Raw HID input reports (over ~\(Int(seconds)) s) ==")
if counter.counts.isEmpty { print("  no gamepad HID devices matched") }
for (k, n) in counter.counts.sorted(by: { $0.key < $1.key }) {
    let ids = (counter.ids[k] ?? [:]).sorted { $0.key < $1.key }.map { String(format: "0x%02x:%d", $0.key, $0.value) }.joined(separator: " ")
    print(String(format: "  %@: %d reports, ~%.0f per second, sizes %@, report IDs %@", k, n, Double(n) / elapsed, "\((counter.sizes[k] ?? []).sorted())", ids))
}
