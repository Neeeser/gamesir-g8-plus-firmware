// Plays a short rumble on each side of the controller through Apple's
// GameController haptics: left handle, then right, then both.
// Run: swift tools/rumble-check.swift
import CoreHaptics
import Foundation
import GameController

GCController.shouldMonitorBackgroundEvents = true
RunLoop.main.run(until: Date().addingTimeInterval(1.5))
guard let c = GCController.controllers().first, let h = c.haptics else { print("no controller with haptics"); exit(1) }
print("Rumbling \(c.vendorName ?? "?") (\(c.productCategory))")
for (label, locality) in [("left", GCHapticsLocality.leftHandle), ("right", .rightHandle), ("both", .handles)] {
    guard let engine = h.createEngine(withLocality: locality) else { print("\(label): no engine"); continue }
    do {
        try engine.start()
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)], relativeTime: 0, duration: 1)
        try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: [])).start(atTime: 0)
        print("\(label): playing 1 s"); RunLoop.main.run(until: Date().addingTimeInterval(1.6)); engine.stop()
    } catch { print("\(label): \(error)") }
}
