import SwiftUI

/// Colors and type. The accent is the controller's own light color for the mode it reports,
/// so the app's color tells the person which mode the controller is in.
enum Theme {
    static let xbox = Color(red: 0.18, green: 0.68, blue: 0.33)
    static let playStation = Color(red: 0.23, green: 0.51, blue: 0.96)
    static let nintendo = Color(red: 0.90, green: 0.28, blue: 0.30)
    static let graphite = Color(red: 0.42, green: 0.45, blue: 0.50)

    /// Fill for a control that has not been pressed yet.
    static let idle = Color.primary.opacity(0.10)

    static func heading(_ style: Font.TextStyle = .title2) -> Font { .system(style, weight: .semibold).width(.expanded) }
    static func number(_ style: Font.TextStyle = .largeTitle) -> Font { .system(style, weight: .semibold).width(.expanded).monospacedDigit() }

    static func settle(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8) }
}

/// What the reported controller type means for the person.
struct Identity {
    let category: String
    let inputs: [String]

    enum Family { case xbox, playStation, nintendo, other }

    var family: Family {
        let c = category.lowercased()
        if c.contains("xbox") { return .xbox }
        if c.contains("dualshock") || c.contains("dualsense") || c.contains("playstation") { return .playStation }
        if c.contains("switch") || c.contains("nintendo") || c.contains("joy-con") { return .nintendo }
        return .other
    }

    var color: Color {
        switch family {
        case .xbox: Theme.xbox
        case .playStation: Theme.playStation
        case .nintendo: Theme.nintendo
        case .other: Theme.graphite
        }
    }

    var glyphs: String {
        switch family {
        case .xbox: "Xbox (A B X Y)"
        case .playStation: "PlayStation"
        case .nintendo: "Nintendo"
        case .other: "Generic"
        }
    }

    var paddles: String {
        let n = inputs.filter { $0.hasPrefix("Paddle") }.count
        return n == 0 ? "Not reported" : "\(n) reported"
    }
}

func shortName(_ name: String) -> String {
    name.replacingOccurrences(of: "Button ", with: "")
        .replacingOccurrences(of: "Direction Pad", with: "D-pad")
        .replacingOccurrences(of: "Thumbstick Button", with: "stick click")
        .replacingOccurrences(of: "Options", with: "View")
}

/// The controller is black plastic, so the drawing keeps the same dark palette in light and dark mode.
extension Theme {
    static let body = Color(red: 0.165, green: 0.173, blue: 0.192)     // #2A2C31 grips
    static let deck = Color(red: 0.102, green: 0.106, blue: 0.118)     // #1A1B1E phone deck
    static let well = Color(red: 0.086, green: 0.090, blue: 0.102)     // #16171A stick wells, capture pill
    static let bumper = Color(red: 0.220, green: 0.231, blue: 0.255)   // #383B41 bumpers, triggers, rear buttons
    static let control = Color(red: 0.278, green: 0.290, blue: 0.318)  // #474A51 buttons not pressed yet
    static let cap = Color(red: 0.333, green: 0.345, blue: 0.376)      // #555860 stick caps
    static let edge = Color.white.opacity(0.09)                        // outline that separates parts on black
    static let label = Color.white.opacity(0.85)
}
