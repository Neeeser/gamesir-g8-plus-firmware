// Pairs a classic Bluetooth controller with this Mac and then leaves the link alone, printing a timeline.
// `blueutil --pair` asks macOS to disconnect right after pairing; the G8 Plus powers off when the host ends a
// link whose HID channel is already up, so pairing that way often loses the controller. This tool never asks
// for a disconnect.
//
// Usage (inside an app bundle, see tools/pair-and-probe.sh):
//   PairHold <address aa-bb-cc-dd-ee-ff> [watch seconds, default 30] [--fresh] [--no-pair]
//     --fresh    remove this Mac's existing pairing for the address first
//     --no-pair  only watch (for a controller that reconnects by itself)
// Prints "FAILED: ..." and exits 1 when the controller never answers or never connects.
import Foundation
import IOBluetooth
import IOKit.hid

setvbuf(stdout, nil, _IOLBF, 0)
let args = Array(CommandLine.arguments.dropFirst())
let flags = Set(args.filter { $0.hasPrefix("--") })
let positional = args.filter { !$0.hasPrefix("--") }
guard let address = positional.first, address.split(separator: "-").count == 6 else {
    print("usage: PairHold <aa-bb-cc-dd-ee-ff> [watch seconds] [--fresh] [--no-pair]"); exit(64)
}
let watchSeconds = positional.count > 1 ? Double(positional[1]) ?? 30 : 30
let fresh = flags.contains("--fresh")
let noPair = flags.contains("--no-pair")
let discoveryLimit = 120.0   // pairing mode lasts about 60 s; allow for the person starting it late

let t0 = Date()
let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm:ss.SSS a"; return f }()
func say(_ s: String) { print("\(clock.string(from: Date())) (+\(String(format: "%6.2f", Date().timeIntervalSince(t0))) s) \(s)") }

// Controllers this project uses identify as Microsoft, Sony or Nintendo depending on the mode.
let controllerVendors: Set<Int> = [0x045e, 0x054c, 0x057e]
var reportCount = 0
var hidPresent = false
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDTransportKey: "Bluetooth"] as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, dev in
    let v = IOHIDDeviceGetProperty(dev, kIOHIDVendorIDKey as CFString) as? Int ?? 0
    let p = IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int ?? 0
    let n = IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "?"
    guard controllerVendors.contains(v) else { return }
    hidPresent = true
    say(String(format: "HID device appeared: %04x:%04x \"%@\"", v, p, n))
}, nil)
IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, dev in
    let v = IOHIDDeviceGetProperty(dev, kIOHIDVendorIDKey as CFString) as? Int ?? 0
    guard controllerVendors.contains(v) else { return }
    hidPresent = false
    say("HID device removed")
}, nil)
IOHIDManagerRegisterInputReportCallback(manager, { _, _, _, _, _, _, _ in reportCount += 1 }, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

final class PairWatcher: NSObject, IOBluetoothDevicePairDelegate {
    var finished = false
    func devicePairingStarted(_ sender: Any!) { say("pairing started") }
    func devicePairingConnecting(_ sender: Any!) { say("pairing: connecting") }
    func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) {
        say("pairing: confirmation request, accepting")
        (sender as? IOBluetoothDevicePair)?.replyUserConfirmation(true)
    }
    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        finished = true
        say(String(format: "pairing finished, result 0x%08x (0 means success). Leaving the link up.", error))
    }
}

final class InquiryWatcher: NSObject, IOBluetoothDeviceInquiryDelegate {
    var sawTarget = false, done = false
    let want: String
    init(want: String) { self.want = want.lowercased() }
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        guard let a = device.addressString?.lowercased(), a == want else { return }
        if !sawTarget { say("found \(a), name \"\(device.name ?? "?")\"") }
        sawTarget = true
        sender.stop()
    }
    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) { done = true }
}

guard let device = IOBluetoothDevice(addressString: address) else { print("FAILED: bad address \(address)"); exit(64) }
say("address \(address): paired on this Mac \(device.isPaired()), connected \(device.isConnected())")
if fresh && device.isPaired() {
    // IOBluetooth has no public call to remove a pairing; `remove` is the method blueutil --unpair uses.
    say("removing this Mac's existing pairing")
    let sel = NSSelectorFromString("remove")
    if device.responds(to: sel) { device.perform(sel) }
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
}

let watcher = PairWatcher()
var pairer: IOBluetoothDevicePair?
if !noPair {
    // The controller answers inquiry only in pairing mode (fast blink).
    say("waiting for the controller in pairing mode (fast blink)")
    let deadline = Date().addingTimeInterval(discoveryLimit)
    var found = false
    while !found && Date() < deadline && !device.isConnected() {
        let iw = InquiryWatcher(want: address)
        let inq = IOBluetoothDeviceInquiry(delegate: iw)!
        inq.updateNewDeviceNames = false
        inq.inquiryLength = 4
        inq.start()
        while !iw.done { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        found = iw.sawTarget
    }
    if device.isConnected() {
        say("controller connected by itself; watching only")
    } else if found {
        pairer = IOBluetoothDevicePair(device: device)
        pairer?.delegate = watcher
        say(String(format: "pairing start returned 0x%08x", pairer?.start() ?? -1))
    } else {
        print("FAILED: \(address) did not answer in \(Int(discoveryLimit)) s. Put the controller in pairing mode (fast blink)."); exit(1)
    }
}

let end = Date().addingTimeInterval(watchSeconds)
var lastConnected = device.isConnected()
var secondsConnected = 0.0, lastTick = Date(), lastStatus = Date(), lastReports = 0
var pairDone: Date?, triedOpen = false
while Date() < end {
    RunLoop.main.run(until: Date().addingTimeInterval(0.25))
    let now = Date(), c = device.isConnected()
    if c { secondsConnected += now.timeIntervalSince(lastTick) }
    lastTick = now
    if c != lastConnected { say(c ? "link up" : "link DOWN"); lastConnected = c }
    if watcher.finished && pairDone == nil { pairDone = now }
    // If the link drops right after pairing, open it once: the controller is still in pairing mode then.
    if let pd = pairDone, !triedOpen, !c, now.timeIntervalSince(pd) > 3 {
        triedOpen = true
        say(String(format: "link down 3 s after pairing; openConnection returned 0x%08x", device.openConnection()))
    }
    if now.timeIntervalSince(lastStatus) >= 5 {
        say("connected \(c), HID present \(hidPresent), input reports in the last 5 s: \(reportCount - lastReports)")
        lastStatus = now; lastReports = reportCount
    }
}
let connected = device.isConnected()
say(String(format: "done. connected %@, HID present %@, connected %.1f of %.0f s, %d input reports",
           connected ? "yes" : "no", hidPresent ? "yes" : "no", secondsConnected, watchSeconds, reportCount))
if !(connected && hidPresent) { print("FAILED: the controller is not connected as a HID device at the end"); exit(1) }
exit(0)
