// Over Bluetooth a DualShock 4 starts with short 0x01 reports (no motion data)
// and switches to full 0x11 reports once the host reads feature report 0x02
// (calibration). This reads that feature report and counts what arrives after.
import Foundation
import IOKit.hid

let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: 0x054c] as CFDictionary)
IOHIDManagerOpen(m, 0)
guard let devs = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>, let d = devs.first else { print("no Sony-ID device found"); exit(1) }
print("device:", IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) ?? "?", IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) ?? "?")
var counts: [UInt8: Int] = [:]; var sizes: [UInt8: Set<Int>] = [:]; var first11: [UInt8] = []
let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 600)
func count(_ seconds: Double, _ label: String) {
    counts = [:]; sizes = [:]
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    print(label, counts.sorted { $0.key < $1.key }.map { String(format: "0x%02x: %d reports (%.0f/s) sizes %@", $0.key, $0.value, Double($0.value)/seconds, "\(sizes[$0.key]!.sorted())") })
}
IOHIDDeviceRegisterInputReportCallback(d, buf, 600, { _, _, _, _, id, report, len in
    let i = UInt8(truncatingIfNeeded: id); counts[i, default: 0] += 1; sizes[i, default: []].insert(len)
    if i == 0x11 && first11.isEmpty { first11 = Array(UnsafeBufferPointer(start: report, count: len)) }
}, nil)
IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
count(3, "before feature read:")
var feat = [UInt8](repeating: 0, count: 64); var len = CFIndex(feat.count)
let r = IOHIDDeviceGetReport(d, kIOHIDReportTypeFeature, 0x02, &feat, &len)
print(String(format: "feature 0x02 read: result 0x%08x, %d bytes: ", r, len) + feat.prefix(len).map { String(format: "%02x", $0) }.joined(separator: " "))
count(4, "after feature read:")
if !first11.isEmpty { print("first 0x11 report:", first11.prefix(40).map { String(format: "%02x", $0) }.joined(separator: " ")) }
