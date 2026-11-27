import XCTest

final class TimingSummaryTests: XCTestCase {
    func testSteadyFifteenMillisecondGaps() throws {
        let times = (0..<101).map { Double($0) * 0.015 }
        let s = try XCTUnwrap(TimingSummary.from(times: times))
        XCTAssertEqual(s.events, 101)
        XCTAssertEqual(s.medianMs, 15, accuracy: 1e-9)
        XCTAssertEqual(s.maxMs, 15, accuracy: 1e-9)
        XCTAssertEqual(s.perSecond, 100 / 1.5, accuracy: 1e-9)
        XCTAssertEqual(s.histogram[3], 100)   // 15 ms falls in the 15-20 ms bucket
    }

    func testTailAndOrdering() throws {
        // 199 gaps of 15 ms and one of 45 ms, given out of order.
        var times = (0..<200).map { Double($0) * 0.015 }
        times.append(times.last! + 0.045)
        times.reverse()
        let s = try XCTUnwrap(TimingSummary.from(times: times))
        XCTAssertEqual(s.medianMs, 15, accuracy: 1e-9)
        XCTAssertEqual(s.maxMs, 45, accuracy: 1e-9)
        XCTAssertEqual(s.p99Ms, 15, accuracy: 1e-9)
        XCTAssertEqual(s.histogram[9], 1)
    }

    func testLastBucketHoldsLongGaps() throws {
        let s = try XCTUnwrap(TimingSummary.from(times: [0, 1]))
        XCTAssertEqual(s.histogram.last, 1)
    }

    func testTooFewEvents() {
        XCTAssertNil(TimingSummary.from(times: []))
        XCTAssertNil(TimingSummary.from(times: [1]))
    }
}

final class AnalyzerTests: XCTestCase {
    func testStickNoiseAndDeadZone() {
        var a = StickAnalyzer()
        for i in 0..<100 { a.add(x: i % 2 == 0 ? 0.01 : -0.01, y: 0) }
        XCTAssertEqual(a.spread.x, 0.01, accuracy: 1e-9)
        XCTAssertEqual(a.spread.y, 0, accuracy: 1e-9)
        a.add(x: 0, y: 0)
        XCTAssertEqual(a.smallestNonzero ?? 0, 0.01, accuracy: 1e-9)
    }

    func testStickReachFullCircle() {
        var a = StickAnalyzer()
        for i in 0..<720 {
            let t = Double(i) / 720 * 2 * .pi
            a.add(x: cos(t), y: sin(t))
        }
        XCTAssertEqual(a.sectorsVisited, StickAnalyzer.sectors)
        XCTAssertEqual(a.averageReach, 1, accuracy: 1e-6)
    }

    func testTriggerSteps() {
        var t = TriggerAnalyzer()
        for i in 0...255 { t.add(Double(i) / 255) }
        XCTAssertEqual(t.steps, 256)
        XCTAssertEqual(t.minValue, 0)
        XCTAssertEqual(t.maxValue, 1)
    }
}

final class LogStoreTests: XCTestCase {
    func testSaveAndLoadRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LogStore(folder: folder)
        var log = RunLog(kind: .timing, title: "Time between updates", firmware: "v12", device: "test", system: "test")
        log.date = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))   // the JSON keeps whole seconds
        log.timing = TimingSummary.from(times: [0, 0.015, 0.030])
        var stick = StickAnalyzer()
        stick.add(x: 0.5, y: -0.5)
        log.leftStick = stick
        let url = try store.save(log)
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].1.lastPathComponent, url.lastPathComponent)
        XCTAssertEqual(loaded[0].0, log)
    }

    func testUnreadableFilesAreSkipped() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: folder.appendingPathComponent("broken.json"))
        XCTAssertTrue(LogStore(folder: folder).load().isEmpty)
    }
}

final class StickReleaseTests: XCTestCase {
    func testMeasuresEdgeToCenter() {
        var r = StickReleaseTracker()
        r.add(distance: 1.0, at: 0.000)
        r.add(distance: 0.95, at: 0.015)
        r.add(distance: 0.6, at: 0.030)    // left the edge here
        r.add(distance: 0.2, at: 0.045)
        r.add(distance: 0.0, at: 0.060)    // back at center
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r.medianMs ?? 0, 30, accuracy: 1e-9)
    }

    func testIgnoresMovesThatNeverReachTheEdge() {
        var r = StickReleaseTracker()
        r.add(distance: 0.5, at: 0)
        r.add(distance: 0.0, at: 0.1)
        XCTAssertEqual(r.count, 0)
    }

    func testGoingBackToTheEdgeRestartsTheClock() {
        var r = StickReleaseTracker()
        r.add(distance: 1.0, at: 0)
        r.add(distance: 0.5, at: 0.1)
        r.add(distance: 1.0, at: 0.2)
        r.add(distance: 0.5, at: 0.3)
        r.add(distance: 0.0, at: 0.35)
        XCTAssertEqual(r.medianMs ?? 0, 50, accuracy: 1e-9)
    }
}
