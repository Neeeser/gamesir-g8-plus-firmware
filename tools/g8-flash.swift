// Flashes a GameSir G8 Plus (Bluetooth model) over Bluetooth LE with the
// controller's own update protocol, as used by the GameSir app and ported
// from jun182/controller-mod-tool (g8ota.py). The controller must be in
// Android mode (yellow light, name "GameSir-G8+"), or in recovery mode
// (screenshot + Start for about 1 s, light blue blink, name "GameSir-G8+_G...")
// with --recovery.
//
//   g8-flash [--recovery] --dry-run      connect, find the update service, subscribe, disconnect
//   g8-flash [--recovery] <ota.bin>      send the image (check it first with tools/flash.sh)
//
// Any failure prints a line starting with "FAILED", which tools/run-app.sh turns into exit status 1.
//
// Protocol on service FF10: commands go to FF11 as [len+3, cmd, 0, payload...]
// and answers come back as FF11 notifications; image data goes to FF12.
//   0x50 start (CRC16-XMODEM big-endian, 24-bit size big-endian) -> status
//   0x51 block size                                              -> status, u16 block size
//   data in 20-byte writes, one block at a time                  -> 0x52 status, u32 next offset
//   0x53 finish                                                  -> status, controller reboots
import CoreBluetooth
import Foundation

let allArgs = Array(CommandLine.arguments.dropFirst())
let recovery = allArgs.contains("--recovery")
let args = allArgs.filter { $0 != "--recovery" }
let dryRun = args.first == "--dry-run"
let image: Data
if dryRun {
    image = Data()
} else {
    guard let path = args.first, let d = FileManager.default.contents(atPath: path), !d.isEmpty, d.count <= 0xFFFFFF else {
        print("usage: g8-flash [--recovery] --dry-run | g8-flash [--recovery] <ota.bin>"); exit(64)
    }
    image = d
}
let deviceName = "GameSir-G8+"
// Android mode advertises exactly "GameSir-G8+"; recovery (G-Touch) mode adds a suffix starting with "_G".
func isTarget(_ name: String?) -> Bool {
    guard let name else { return false }
    return recovery ? name.hasPrefix(deviceName + "_G") : name == deviceName
}
let modeHint = recovery ? "recovery mode, light blue blink" : "Android mode, yellow light"
let writeSlice = 20
let responseTimeout = 3.0
let maxSameBlock = 5

func crc16xmodem(_ data: Data) -> UInt16 {
    var crc: UInt16 = 0
    for b in data {
        crc ^= UInt16(b) << 8
        for _ in 0..<8 { crc = crc & 0x8000 != 0 ? (crc << 1) ^ 0x1021 : crc << 1 }
    }
    return crc
}
func frame(_ cmd: UInt8, _ payload: [UInt8] = []) -> Data { Data([UInt8(payload.count + 3), cmd, 0] + payload) }
func log(_ s: String) { print(s); fflush(stdout) }

final class Flasher: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var central: CBCentralManager!
    var peripheral: CBPeripheral?
    var control: CBCharacteristic?
    var dataChar: CBCharacteristic?
    var expected: UInt8 = 0
    var deadline: Date?
    var blockSize = 0
    var offset = 0, lastOffset = -1, same = 0   // byte offset of the block being sent
    var pending: [Data] = []           // 20-byte pieces of the current block not yet written
    let started = Date()
    var lastPercent = -1

    override init() { super.init(); central = CBCentralManager(delegate: self, queue: .main) }

    func fail(_ msg: String) -> Never {
        log("FAILED: \(msg)")
        log("The controller keeps its current firmware if a transfer stops before the finish command (JieLi dual-bank update, inferred). If it does not boot normally, hold screenshot + Start for about 1 s for recovery mode and reflash with --recovery (untested from this Mac).")
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        exit(1)
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { log("Bluetooth state \(c.state.rawValue)"); return }
        // A bonded controller may already be connected to this Mac and then does not advertise.
        let known = c.retrieveConnectedPeripherals(withServices: [CBUUID(string: "FF10"), CBUUID(string: "1812"), CBUUID(string: "180A")])
        if let p = known.first(where: { isTarget($0.name) }) { log("Using connected \(p.name ?? deviceName)"); connect(p); return }
        log("Scanning for \(deviceName) (\(modeHint))...")
        c.scanForPeripherals(withServices: nil)
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = (ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name
        guard isTarget(name), peripheral == nil else { return }
        log("Found \(name ?? deviceName) (\(p.identifier.uuidString)), signal \(rssi) dBm"); c.stopScan(); connect(p)
    }
    func connect(_ p: CBPeripheral) { peripheral = p; p.delegate = self; central.connect(p) }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { p.discoverServices([CBUUID(string: "FF10")]) }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { fail("connect: \(error?.localizedDescription ?? "?")") }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        // After the finish command the controller reboots into the new image, and the link can drop before its
        // answer arrives. That is the expected end of an update, not a failure, but it is not confirmed either.
        // `deadline` is set only once send(0x53) has written the command.
        if expected == 0x53 && deadline != nil {
            log("Finish command sent; the controller dropped the link before answering (it reboots after an update). Done in \(Int(Date().timeIntervalSince(started))) s, not confirmed: check that it starts normally.")
            exit(0)
        }
        fail("disconnected: \(error?.localizedDescription ?? "no error given")")
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == CBUUID(string: "FF10") }) else { fail("no FF10 update service") }
        p.discoverCharacteristics([CBUUID(string: "FF11"), CBUUID(string: "FF12")], for: s)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        control = s.characteristics?.first { $0.uuid == CBUUID(string: "FF11") }
        dataChar = s.characteristics?.first { $0.uuid == CBUUID(string: "FF12") }
        guard let control, let dataChar, control.properties.contains(.notify) else { fail("FF11/FF12 missing or FF11 cannot notify") }
        log("FF11 properties 0x\(String(control.properties.rawValue, radix: 16)), FF12 properties 0x\(String(dataChar.properties.rawValue, radix: 16)), max write \(p.maximumWriteValueLength(for: .withoutResponse)) bytes")
        p.setNotifyValue(true, for: control)
    }
    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if let error { fail("subscribe: \(error.localizedDescription)") }
        if dryRun { log("Dry run OK: update service found and subscribed. Nothing was sent."); central.cancelPeripheralConnection(p); exit(0) }
        let crc = crc16xmodem(image), n = image.count
        log("Image \(n) bytes, CRC16 \(String(format: "%04x", crc)). Starting.")
        send(0x50, [UInt8(crc >> 8), UInt8(crc & 0xff), UInt8(n >> 16 & 0xff), UInt8(n >> 8 & 0xff), UInt8(n & 0xff)])
    }

    func write(_ ch: CBCharacteristic, _ value: Data) {
        let type: CBCharacteristicWriteType = ch.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral!.writeValue(value, for: ch, type: type)
    }
    func send(_ cmd: UInt8, _ payload: [UInt8] = []) {
        expected = cmd; deadline = Date().addingTimeInterval(responseTimeout)
        write(control!, frame(cmd, payload))
    }
    func sendBlock() {
        same = offset == lastOffset ? same + 1 : 0
        if same > maxSameBlock { fail("controller asked for offset \(offset) more than \(maxSameBlock) times") }
        lastOffset = offset
        let end = min(offset + blockSize, image.count)
        let piece = image.subdata(in: offset..<end)
        pending = stride(from: 0, to: piece.count, by: writeSlice).map { piece.subdata(in: $0..<min($0 + writeSlice, piece.count)) }
        expected = 0x52; deadline = nil
        pump()
    }
    // Write-without-response pieces as fast as CoreBluetooth's queue allows.
    func pump() {
        guard let p = peripheral, let dataChar else { return }
        while !pending.isEmpty && (p.canSendWriteWithoutResponse || !dataChar.properties.contains(.writeWithoutResponse)) {
            write(dataChar, pending.removeFirst())
        }
        if pending.isEmpty && deadline == nil { deadline = Date().addingTimeInterval(responseTimeout) }
    }
    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) { pump() }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == CBUUID(string: "FF11"), let v = ch.value, v.count >= 3 else { return }
        let b = [UInt8](v)
        guard b[1] == expected else { return }   // like the app: ignore answers to other commands
        switch b[1] {
        case 0x50:
            if b[2] != 0 { fail("start refused, status \(b[2])") }
            send(0x51)
        case 0x51:
            guard b.count >= 5, b[2] == 0 else { fail("block size answer \(v.map { String(format: "%02x", $0) })") }
            blockSize = Int(b[3]) << 8 | Int(b[4])
            if blockSize == 0 { fail("block size 0") }
            log("Block size \(blockSize), \((image.count + blockSize - 1) / blockSize) blocks")
            offset = 0; sendBlock()
        case 0x52:
            guard b.count >= 8 else { fail("short block answer") }
            if b[3] != 0 { fail("block at offset \(offset) status \(b[3])") }
            let next = Int(b[4]) << 24 | Int(b[5]) << 16 | Int(b[6]) << 8 | Int(b[7])
            if next > image.count { fail("controller asked for offset \(next), past the end of the \(image.count)-byte image") }
            let pct = min(100, next * 100 / image.count)
            if pct / 5 != lastPercent / 5 { log("  \(pct)% (\(next) bytes, \(Int(Date().timeIntervalSince(started))) s)"); lastPercent = pct }
            // Resume exactly where the controller asks, even mid-block, so no bytes are skipped.
            offset = next
            if offset >= image.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.send(0x53) }
                expected = 0x53; deadline = nil
            } else { sendBlock() }
        case 0x53:
            if b[2] != 0 { fail("finish refused, status \(b[2])") }
            log("Done in \(Int(Date().timeIntervalSince(started))) s. The controller should reboot into the new firmware.")
            exit(0)
        default: break
        }
    }

    func checkTimeout() {
        if let d = deadline, Date() > d { fail(String(format: "timed out waiting for the 0x%02x answer", expected)) }
    }
}

let flasher = Flasher()
Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in flasher.checkTimeout() }
RunLoop.main.run(until: Date().addingTimeInterval(dryRun ? 60 : 900))
log("FAILED: gave up after the overall time limit"); exit(2)
