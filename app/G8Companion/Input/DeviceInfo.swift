import Foundation

enum DeviceInfo {
    /// Hardware model identifier, such as iPhone19,4 or Mac15,3.
    static var model: String {
        #if os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
        #else
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim + " (simulator)" }
        var u = utsname()
        uname(&u)
        return withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        #endif
    }

    static var system: String {
        #if os(macOS)
        "macOS " + ProcessInfo.processInfo.operatingSystemVersionString
        #else
        "iOS " + ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }
}
