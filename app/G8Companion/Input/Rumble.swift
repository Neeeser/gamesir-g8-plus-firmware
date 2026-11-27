import CoreHaptics
import GameController

/// Plays short rumble pulses through the controller's motors, the same path games use.
@MainActor
final class Rumble {
    private var engines: [GCHapticsLocality: CHHapticEngine] = [:]
    private weak var controller: GCController?

    func localities(of c: GCController?) -> Set<GCHapticsLocality> {
        c?.haptics?.supportedLocalities ?? []
    }

    /// Returns nil on success, or a message that says what went wrong.
    func pulse(_ c: GCController, locality: GCHapticsLocality, strength: Float, seconds: Double = 0.6) -> String? {
        if controller !== c { engines = [:]; controller = c }
        guard let haptics = c.haptics else { return "This controller reports no rumble motors." }
        do {
            let engine: CHHapticEngine
            if let e = engines[locality] {
                engine = e
            } else {
                guard let e = haptics.createEngine(withLocality: locality) else { return "No motor at that position." }
                engine = e
                engines[locality] = e
            }
            try engine.start()
            let event = CHHapticEvent(eventType: .hapticContinuous,
                                      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: strength),
                                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)],
                                      relativeTime: 0, duration: seconds)
            let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
            return nil
        } catch {
            engines[locality] = nil
            return error.localizedDescription
        }
    }
}
