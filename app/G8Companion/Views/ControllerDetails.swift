import GameController
import SwiftUI

struct ControllerDetails: View {
    @Environment(AppModel.self) private var model
    @Environment(ControllerMonitor.self) private var monitor
    @State private var strength: Float = 0.8
    @State private var rumbleMessage: String?
    #if os(iOS) && targetEnvironment(simulator)
    @State private var virtualController: GCVirtualController?
    #endif

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                TextField("Firmware on the controller, such as v12", text: $model.firmware)
                    .autocorrectionDisabled()
            } header: {
                Text("Firmware")
            } footer: {
                Text("Saved with every log, so runs from different builds can be compared.")
            }

            Section("Connected") {
                NoControllerNote()
                if monitor.controllers.count > 1 {
                    Picker("Controller", selection: Binding(
                        get: { monitor.current.map(ObjectIdentifier.init) },
                        set: { id in monitor.select(monitor.controllers.first { ObjectIdentifier($0) == id }) })) {
                        ForEach(monitor.controllers, id: \.self) { c in
                            Text(c.vendorName ?? "Controller").tag(Optional(ObjectIdentifier(c)))
                        }
                    }
                }
                if let c = monitor.current {
                    let info = monitor.info(c)
                    LabeledContent("Name", value: info.name)
                    LabeledContent("Type", value: info.category)
                    LabeledContent("Buttons shown as", value: Identity(category: info.category, inputs: info.inputNames).glyphs)
                    if let p = info.batteryPercent {
                        LabeledContent("Battery", value: "\(p)%" + (info.batteryState.map { ", \($0)" } ?? ""))
                    }
                    LabeledContent("Paddles", value: Identity(category: info.category, inputs: info.inputNames).paddles)
                }
            }

            if let c = monitor.current {
                Section {
                    let places = model.rumble.localities(of: c)
                    Slider(value: $strength, in: 0.1...1) { Text("Strength") }
                    HStack {
                        rumbleButton("Left", c, .leftHandle, enabled: places.contains(.leftHandle))
                        rumbleButton("Right", c, .rightHandle, enabled: places.contains(.rightHandle))
                        rumbleButton("Both", c, .handles, enabled: places.contains(.handles) || places.contains(.default))
                    }
                    .buttonStyle(.bordered)
                    if let rumbleMessage { Text(rumbleMessage).foregroundStyle(.secondary) }
                    if places.isEmpty { Text("This controller reports no rumble motors to the system.").foregroundStyle(.secondary) }
                } header: {
                    Text("Rumble")
                }

                Section("Inputs the system sees") {
                    Text(monitor.reported.joined(separator: ", "))
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }

            #if os(iOS) && targetEnvironment(simulator)
            Section("Simulator") {
                Toggle("On-screen controller", isOn: Binding(
                    get: { virtualController != nil },
                    set: { on in
                        if on {
                            let config = GCVirtualController.Configuration()
                            config.elements = [GCInputLeftThumbstick, GCInputRightThumbstick, GCInputButtonA, GCInputButtonB,
                                               GCInputButtonX, GCInputButtonY, GCInputLeftShoulder, GCInputRightShoulder,
                                               GCInputLeftTrigger, GCInputRightTrigger, GCInputDirectionPad]
                            let v = GCVirtualController(configuration: config)
                            v.connect()
                            virtualController = v
                        } else {
                            virtualController?.disconnect()
                            virtualController = nil
                        }
                    }))
            }
            #endif
        }
        .formStyle(.grouped)
        .navigationTitle("Controller details")
    }

    private func rumbleButton(_ title: String, _ c: GCController, _ place: GCHapticsLocality, enabled: Bool) -> some View {
        Button(title) { rumbleMessage = model.rumble.pulse(c, locality: enabled ? place : .default, strength: strength) }
    }
}
