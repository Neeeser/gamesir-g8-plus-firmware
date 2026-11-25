// Prints each button press and the full range each trigger and stick reaches,
// as Apple's GameController framework reports them. Use it to check that a
// patched mode maps every physical control correctly.
// Run: swift tools/input-check.swift [seconds]
import Foundation
import GameController

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "") ?? 30
GCController.shouldMonitorBackgroundEvents = true
var ranges: [String: (Float, Float)] = [:]
var hooked = Set<ObjectIdentifier>()

func hook(_ c: GCController) {
    guard hooked.insert(ObjectIdentifier(c)).inserted else { return }
    print("Listening to \(c.vendorName ?? "?") (\(c.productCategory)) for \(Int(seconds)) s. Press every button, pull both triggers slowly, move both sticks.")
    for (name, element) in c.physicalInputProfile.elements {
        if let b = element as? GCControllerButtonInput {
            b.pressedChangedHandler = { _, value, pressed in
                if pressed { print("pressed  \(name)") }
                if b.isAnalog { let r = ranges[name] ?? (1, 0); ranges[name] = (min(r.0, value), max(r.1, value)) }
            }
            if b.isAnalog {
                b.valueChangedHandler = { _, value, _ in let r = ranges[name] ?? (1, 0); ranges[name] = (min(r.0, value), max(r.1, value)) }
            }
        } else if let a = element as? GCControllerAxisInput {
            a.valueChangedHandler = { _, value in let r = ranges[name] ?? (0, 0); ranges[name] = (min(r.0, value), max(r.1, value)) }
        }
    }
}
NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { n in
    if let c = n.object as? GCController { hook(c) }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 1) { GCController.controllers().forEach(hook) }
RunLoop.main.run(until: Date().addingTimeInterval(seconds))
print("-- range reached by each analog control (min to max) --")
for (k, r) in ranges.sorted(by: { $0.key < $1.key }) where !k.hasSuffix("Up") && !k.hasSuffix("Down") && !k.hasSuffix("Left") && !k.hasSuffix("Right") {
    print(String(format: "  %@: %.2f to %.2f", k, r.0, r.1))
}
