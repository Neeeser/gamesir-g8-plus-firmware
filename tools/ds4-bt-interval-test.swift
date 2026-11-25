// Tests whether the controller honors the DualShock 4 Bluetooth report
// interval that a host can request in output report 0x11 (byte 1 = 0xC0 |
// interval in ms; Linux's hid-sony driver uses this). The request lasts only
// for the current connection. Rumble is sent as zero; the light bar is untouched.
// Run: swift tools/ds4-bt-interval-test.swift [interval-ms ...]
import Foundation
import IOKit.hid

let intervals = CommandLine.arguments.dropFirst().compactMap { UInt8($0) }
let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: 0x054c] as CFDictionary)
IOHIDManagerOpen(m, 0)
guard let d = (IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>)?.first else { print("no Sony-ID device"); exit(1) }

func crc32(_ bytes: [UInt8]) -> UInt32 {
    var c: UInt32 = 0xffff_ffff
    for b in bytes { c ^= UInt32(b); for _ in 0..<8 { c = (c >> 1) ^ (0xedb8_8320 & (0 &- (c & 1))) } }
    return ~c
}
var n11 = 0; var gaps: [Double] = []; var last = 0.0
let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 600)
IOHIDDeviceRegisterInputReportCallback(d, buf, 600, { _, _, _, _, id, _, _ in
    guard id == 0x11 else { return }
    let t = ProcessInfo.processInfo.systemUptime
    if last > 0 { gaps.append((t - last) * 1000) }; last = t; n11 += 1
}, nil)
IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

func measure(_ label: String) {
    n11 = 0; gaps = []; last = 0
    RunLoop.main.run(until: Date().addingTimeInterval(4))
    let s = gaps.sorted()
    let pct = { (p: Double) in s.isEmpty ? 0 : s[min(s.count - 1, Int(Double(s.count) * p))] }
    print(String(format: "%@: %d full reports in 4 s (%.0f/s); gap between reports median %.1f ms, 95th percentile %.1f ms, max %.1f ms",
                 label, n11, Double(n11) / 4, pct(0.5), pct(0.95), s.last ?? 0))
}

// Feature report 0x02 switches the controller to full 0x11 reports.
var feat = [UInt8](repeating: 0, count: 64); var flen = CFIndex(64)
_ = IOHIDDeviceGetReport(d, kIOHIDReportTypeFeature, 0x02, &feat, &flen)
measure("default")
for ms in intervals {
    var out = [UInt8](repeating: 0, count: 78)
    out[0] = 0x11; out[1] = 0xC0 | (ms & 0x3f); out[3] = 0x01  // flag 0x01: rumble fields valid (both zero)
    let crc = crc32([0xA2] + out[0..<74])
    for i in 0..<4 { out[74 + i] = UInt8(truncatingIfNeeded: crc >> (8 * UInt32(i))) }
    let r = IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, 0x11, out, out.count)
    print(String(format: "requested %d ms interval: result 0x%08x", ms, r))
    measure("after requesting \(ms) ms")
}
