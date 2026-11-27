import Foundation

#if os(macOS)
import IOKit.hid

/// Mac only: counts every HID input report from a controller, with the kernel's timestamp.
/// GameController can skip states that do not change anything; raw reports show the real link rate.
final class RawReports: @unchecked Sendable {
    /// Vendors the G8 Plus reports as, depending on its mode: Microsoft, Sony, Nintendo, GameSir.
    static let vendors = [0x045e, 0x054c, 0x057e, 0x3537]

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let lock = NSLock()
    private var times: [Double] = []
    private var recording = false
    private let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1e9
    }()

    init() {
        let matches = Self.vendors.map { [kIOHIDVendorIDKey: $0] as CFDictionary }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputReportWithTimeStampCallback(manager, { context, _, _, _, _, _, _, stamp in
            guard let context else { return }
            Unmanaged<RawReports>.fromOpaque(context).takeUnretainedValue().add(stamp)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func add(_ stamp: UInt64) {
        lock.lock(); defer { lock.unlock() }
        if recording { times.append(Double(stamp) * timebase) }
    }

    func start() {
        lock.lock(); times = []; recording = true; lock.unlock()
    }

    func stop() -> TimingSummary? {
        lock.lock(); recording = false; let t = times; lock.unlock()
        return TimingSummary.from(times: t)
    }
}
#endif
