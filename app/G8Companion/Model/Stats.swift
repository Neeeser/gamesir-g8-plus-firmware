import Foundation

/// Summary of the gaps between input events, in milliseconds.
struct TimingSummary: Codable, Equatable {
    var events: Int
    var seconds: Double
    var perSecond: Double
    var medianMs: Double
    var p95Ms: Double
    var p99Ms: Double
    var maxMs: Double
    var minMs: Double
    /// Count of gaps per bucket; bucket i covers [i * bucketMs, (i + 1) * bucketMs), the last bucket holds everything above.
    var histogram: [Int]
    var bucketMs: Double

    /// Builds a summary from event times in seconds, in the order they arrived.
    /// Returns nil when there are fewer than two events, since no gap exists.
    static func from(times: [Double], bucketMs: Double = 5, buckets: Int = 12) -> TimingSummary? {
        guard times.count >= 2 else { return nil }
        let sorted = times.sorted()
        var gaps: [Double] = []
        gaps.reserveCapacity(sorted.count - 1)
        for i in 1..<sorted.count { gaps.append((sorted[i] - sorted[i - 1]) * 1000) }
        let g = gaps.sorted()
        let span = sorted.last! - sorted.first!
        var hist = Array(repeating: 0, count: buckets)
        // The small offset keeps a gap of exactly 15 ms, stored as 14.99999..., in the 15 ms bucket.
        for gap in gaps { hist[min(buckets - 1, max(0, Int(gap / bucketMs + 1e-6)))] += 1 }
        return TimingSummary(events: times.count, seconds: span,
                             perSecond: span > 0 ? Double(gaps.count) / span : 0,
                             medianMs: percentile(g, 0.5), p95Ms: percentile(g, 0.95),
                             p99Ms: percentile(g, 0.99), maxMs: g.last!, minMs: g.first!,
                             histogram: hist, bucketMs: bucketMs)
    }

    /// Nearest-rank percentile of an already sorted array.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((p * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(sorted.count - 1, max(0, rank))]
    }
}

/// Collects stick samples (each axis -1...1) and reports noise, dead zone and reach.
struct StickAnalyzer: Codable, Equatable {
    static let sectors = 36
    var samples = 0
    var minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0
    /// Smallest nonzero distance from center seen. With a firmware dead zone the stick jumps from 0 straight to this value.
    var smallestNonzero: Double?
    /// Largest distance from center seen in each 10-degree sector, for the reach (circularity) plot.
    var reach = Array(repeating: 0.0, count: sectors)
    private var sumX = 0.0, sumY = 0.0, sumX2 = 0.0, sumY2 = 0.0

    mutating func add(x: Double, y: Double) {
        samples += 1
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        sumX += x; sumY += y; sumX2 += x * x; sumY2 += y * y
        let r = (x * x + y * y).squareRoot()
        if r > 0 { smallestNonzero = min(smallestNonzero ?? r, r) }
        var angle = atan2(y, x)
        if angle < 0 { angle += 2 * .pi }
        let sector = min(Self.sectors - 1, Int(angle / (2 * .pi) * Double(Self.sectors)))
        reach[sector] = max(reach[sector], min(r, 1.5))
    }

    /// Standard deviation of each axis; for a stick at rest this is its noise.
    var spread: (x: Double, y: Double) {
        guard samples > 1 else { return (0, 0) }
        let n = Double(samples)
        func sd(_ s: Double, _ s2: Double) -> Double { max(0, s2 / n - (s / n) * (s / n)).squareRoot() }
        return (sd(sumX, sumX2), sd(sumY, sumY2))
    }

    /// Average reach over sectors that were visited, 1.0 for a stick that reaches the full circle.
    var averageReach: Double {
        let visited = reach.filter { $0 > 0.2 }
        return visited.isEmpty ? 0 : visited.reduce(0, +) / Double(visited.count)
    }

    var sectorsVisited: Int { reach.filter { $0 > 0.2 }.count }
}

/// Collects trigger samples (0...1).
struct TriggerAnalyzer: Codable, Equatable {
    var minValue = 1.0, maxValue = 0.0
    var distinct = Set<Int>()   // values in steps of 1/1024, enough to count an 8- or 10-bit trigger's steps

    mutating func add(_ v: Double) {
        minValue = min(minValue, v); maxValue = max(maxValue, v)
        distinct.insert(Int((v * 1024).rounded()))
    }

    var steps: Int { distinct.count }
}

/// Measures how long a stick takes to get back to center after it is let go from the edge.
/// Stick smoothing in the firmware adds a tail to this return, so it is the number that shows a smoothing change.
/// The stick's own spring is part of every reading, so compare builds, not absolute values.
struct StickReleaseTracker: Codable, Equatable {
    static let edge = 0.9      // counts as held at the edge above this distance from center
    static let center = 0.05   // counts as back at center below this

    private(set) var releasesMs: [Double] = []
    private var armed = false
    private var leftEdgeAt: Double?

    /// Feed every input state: distance from center (0...1) and the state's timestamp in seconds.
    mutating func add(distance r: Double, at t: Double) {
        if r >= Self.edge {
            armed = true
            leftEdgeAt = nil
        } else if armed {
            if leftEdgeAt == nil { leftEdgeAt = t }
            if r <= Self.center, let start = leftEdgeAt {
                releasesMs.append((t - start) * 1000)
                armed = false
                leftEdgeAt = nil
            }
        }
    }

    var count: Int { releasesMs.count }
    var medianMs: Double? { releasesMs.isEmpty ? nil : TimingSummary.percentile(releasesMs.sorted(), 0.5) }
}
