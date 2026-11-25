// Prints every distinct raw HID input report from gamepads with the given
// USB vendor ID (hex), with a timestamp, so a report layout can be worked
// out by pressing one control at a time.
// Run: swift tools/hid-dump.swift <vendor-hex> [seconds]
import Foundation
import IOKit.hid

let vendor = Int(CommandLine.arguments.dropFirst().first ?? "", radix: 16) ?? 0x045e
let seconds = Double(CommandLine.arguments.dropFirst(2).first ?? "") ?? 30
let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: vendor] as CFDictionary)
IOHIDManagerOpen(m, 0)
guard let devices = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>, !devices.isEmpty else { print("no device with vendor \(String(vendor, radix: 16))"); exit(1) }
let start = Date()
var last: [UInt8] = []
let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
for d in devices {
    if let desc = IOHIDDeviceGetProperty(d, kIOHIDReportDescriptorKey as CFString) as? Data {
        print("report descriptor (\(desc.count) bytes): " + desc.map { String(format: "%02x", $0) }.joined())
    }
    IOHIDDeviceRegisterInputReportCallback(d, buf, 1024, { _, _, _, _, id, report, len in
        let bytes = Array(UnsafeBufferPointer(start: report, count: len))
        guard bytes != last else { return }
        last = bytes
        print(String(format: "%6.2f id %02x: ", Date().timeIntervalSince(start), id) + bytes.map { String(format: "%02x", $0) }.joined(separator: " "))
        fflush(stdout)
    }, nil)
    IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
}
RunLoop.main.run(until: Date().addingTimeInterval(seconds))
