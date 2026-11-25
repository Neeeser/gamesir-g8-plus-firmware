// Read-only look at a controller's Bluetooth LE side: advertisement data,
// every GATT service and characteristic, and the value of each readable
// characteristic (firmware version lives in Device Information, 0x180A).
// It never writes or subscribes, so it cannot change the controller.
// Run: swift tools/ble-inspect.swift [name-substring | "*" to list all] [seconds]
import CoreBluetooth
import Foundation

let match = CommandLine.arguments.dropFirst().first ?? "GameSir"
let seconds = Double(CommandLine.arguments.dropFirst(2).first ?? "") ?? 30

func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined(separator: " ") }
func text(_ d: Data) -> String {
    // Show a text rendering only when every byte is printable ASCII (trailing zeros allowed).
    let body = d.reversed().drop(while: { $0 == 0 }).reversed()
    guard !body.isEmpty, body.allSatisfy({ (0x20...0x7e).contains($0) }) else { return "" }
    return "  \"\(String(decoding: body, as: UTF8.self))\""
}

final class Inspector: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var central: CBCentralManager!
    var target: CBPeripheral?
    var pendingReads = 0
    var servicesLeft = 0
    var listed = Set<UUID>()

    override init() { super.init(); central = CBCentralManager(delegate: self, queue: .main) }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { print("Bluetooth state: \(c.state.rawValue) (4 = off, 3 = not allowed)"); return }
        // A controller already connected to this Mac does not advertise; check those too.
        let known = c.retrieveConnectedPeripherals(withServices: [CBUUID(string: "180A"), CBUUID(string: "1812"), CBUUID(string: "FF10")])
        if let p = known.first(where: { ($0.name ?? "").localizedCaseInsensitiveContains(match) }) {
            print("Already connected: \(p.name ?? "?")"); connect(p); return
        }
        print("Scanning for a device whose name contains \"\(match)\"...")
        c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = (ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        // "*" lists every advertiser once instead of connecting to one.
        if match == "*" {
            if listed.insert(p.identifier).inserted { print("  \(name.isEmpty ? "(no name)" : name) RSSI \(rssi) services \(ad[CBAdvertisementDataServiceUUIDsKey] ?? "-")") }
            return
        }
        guard name.localizedCaseInsensitiveContains(match), target == nil else { return }
        print("Found \"\(name)\" RSSI \(rssi)")
        for (k, v) in ad.sorted(by: { $0.key < $1.key }) {
            if let d = v as? Data { print("  adv \(k): \(hex(d))") } else { print("  adv \(k): \(v)") }
        }
        c.stopScan(); connect(p)
    }

    func connect(_ p: CBPeripheral) { target = p; p.delegate = self; central.connect(p) }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        print("Connected; discovering services"); p.discoverServices(nil)
    }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        print("Connect failed: \(error?.localizedDescription ?? "?")"); exit(1)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        let services = p.services ?? []
        servicesLeft = services.count
        for s in services { p.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        print("service \(s.uuid)\(s.isPrimary ? "" : " (secondary)")")
        for ch in s.characteristics ?? [] {
            print("  characteristic \(ch.uuid) properties 0x\(String(ch.properties.rawValue, radix: 16))")
            if ch.properties.contains(.read) { pendingReads += 1; p.readValue(for: ch) }
        }
        servicesLeft -= 1
        finishIfDone()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if let error { print("  read \(ch.service?.uuid.uuidString ?? "")/\(ch.uuid): \(error.localizedDescription)") }
        else if let v = ch.value { print("  read \(ch.service?.uuid.uuidString ?? "")/\(ch.uuid): \(hex(v))\(text(v))") }
        pendingReads -= 1
        finishIfDone()
    }

    func finishIfDone() {
        guard servicesLeft == 0, pendingReads == 0, let p = target else { return }
        central.cancelPeripheralConnection(p)
        print("Done; disconnected."); exit(0)
    }
}

let inspector = Inspector()
RunLoop.main.run(until: Date().addingTimeInterval(seconds))
print("Timed out after \(Int(seconds)) s"); exit(2)
