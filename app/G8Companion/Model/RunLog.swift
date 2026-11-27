import Foundation

/// One saved test run. Written as a JSON file so runs can be compared across firmware builds
/// and copied off the phone (Files app, or `xcrun devicectl device copy from`).
struct RunLog: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case timing, sticks, triggers, buttons, idle, rumble, release
    }

    var id = UUID()
    var date = Date()
    var kind: Kind
    var title: String
    /// What the person typed as the firmware on the controller, such as a build name.
    var firmware: String
    var device: String
    var system: String
    var controller: ControllerInfo?
    var timing: TimingSummary?
    var rawTiming: TimingSummary?
    var leftStick: StickAnalyzer?
    var rightStick: StickAnalyzer?
    var leftRelease: StickReleaseTracker?
    var rightRelease: StickReleaseTracker?
    var leftTrigger: TriggerAnalyzer?
    var rightTrigger: TriggerAnalyzer?
    var buttonsSeen: [String]?
    var buttonsMissing: [String]?
    var pressedTogether: [String]?
    var notes: [String] = []
}

struct ControllerInfo: Codable, Equatable {
    var name: String
    var category: String
    var batteryPercent: Int?
    var batteryState: String?
    var inputNames: [String]
}

/// Reads and writes run logs in one folder.
struct LogStore {
    let folder: URL

    static func defaultFolder() -> URL {
        #if os(macOS)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("G8 Companion", isDirectory: true)
        #else
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
        return base.appendingPathComponent("Logs", isDirectory: true)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func fileURL(for log: RunLog) -> URL {
        let stamp = ISO8601DateFormatter.string(from: log.date, timeZone: .current,
                                                formatOptions: [.withFullDate, .withTime])
        return folder.appendingPathComponent("\(stamp)-\(log.kind.rawValue)-\(log.id.uuidString.prefix(4)).json")
    }

    @discardableResult
    func save(_ log: RunLog) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = fileURL(for: log)
        try Self.encoder.encode(log).write(to: url, options: .atomic)
        return url
    }

    /// All logs, newest first. Files that fail to decode are skipped.
    func load() -> [(RunLog, URL)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Self.decoder.decode(RunLog.self, from: Data(contentsOf: url))).map { ($0, url) } }
            .sorted { $0.0.date > $1.0.date }
    }

    func delete(_ url: URL) throws { try FileManager.default.removeItem(at: url) }
}
