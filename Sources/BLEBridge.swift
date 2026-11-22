import Foundation
import CoreBluetooth
import UIKit

/// Setzt die Web-Bluetooth-Aufrufe aus bridge.js auf CoreBluetooth um.
final class BLEBridge: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    var reply: (Int, Bool, Any) -> Void = { _, _, _ in }
    var emit: (String, [String: Any]) -> Void = { _, _ in }
    weak var host: UIViewController?

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var advNames: [UUID: String] = [:]
    private var connected = Set<UUID>()
    private var watchers = Set<UUID>()
    private var stateWaiters: [() -> Void] = []
    private var waiters: [String: [Int]] = [:]
    private var connectTimers: [UUID: DispatchWorkItem] = [:]
    private var picker: DevicePicker?
    private var pickerActive = false
    private let knownKey = "knownDevices"

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: Hilfen

    private func ok(_ id: Int, _ payload: Any = NSNull()) { reply(id, true, payload) }

    private func fail(_ id: Int, _ msg: String, _ name: String = "NetworkError") {
        reply(id, false, ["name": name, "message": msg])
    }

    private func norm(_ u: CBUUID) -> String { u.uuidString.lowercased() }

    private func cbuuid(_ s: String) -> CBUUID? {
        let valid = [4, 8, 36].contains(s.count) && s.allSatisfy { $0.isHexDigit || $0 == "-" }
        return valid ? CBUUID(string: s) : nil
    }

    private func key(_ kind: String, _ p: UUID, _ parts: String...) -> String {
        ([kind, p.uuidString] + parts).joined(separator: "|")
    }

    private func ckey(_ kind: String, _ p: CBPeripheral, _ c: CBCharacteristic) -> String {
        let s: CBService? = c.service
        return key(kind, p.identifier, s.map { norm($0.uuid) } ?? "", norm(c.uuid))
    }

    private func wait(_ k: String, _ id: Int) { waiters[k, default: []].append(id) }

    private func finish(_ k: String, success: Bool, payload: Any = NSNull(), error: String = "", name: String = "NetworkError") {
        guard let ids = waiters.removeValue(forKey: k) else { return }
        for id in ids {
            if success { ok(id, payload) } else { fail(id, error, name) }
        }
    }

    private func failAll(for p: UUID, _ msg: String) {
        for k in Array(waiters.keys) where k.contains(p.uuidString) {
            finish(k, success: false, error: msg)
        }
    }

    private var known: [[String: String]] {
        get { UserDefaults.standard.array(forKey: knownKey) as? [[String: String]] ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: knownKey) }
    }

    private func remember(_ id: UUID, _ name: String) {
        var list = known.filter { $0["id"] != id.uuidString }
        list.append(["id": id.uuidString, "name": name])
        known = list
    }

    private func register(_ p: CBPeripheral) {
        peripherals[p.identifier] = p
        p.delegate = self
    }

    private func devUUID(_ m: [String: Any]) -> UUID? {
        (m["dev"] as? String).flatMap { UUID(uuidString: $0) }
    }

    private func periph(_ u: UUID) -> CBPeripheral? {
        if let p = peripherals[u] { return p }
        if let p = central.retrievePeripherals(withIdentifiers: [u]).first {
            register(p)
            return p
        }
        return nil
    }

    private func lookup(_ m: [String: Any]) -> (CBPeripheral, CBCharacteristic)? {
        guard let u = devUUID(m), let p = periph(u),
              let s = (m["svc"] as? String)?.lowercased(),
              let c = (m["chr"] as? String)?.lowercased(),
              let service = p.services?.first(where: { norm($0.uuid) == s }),
              let ch = service.characteristics?.first(where: { norm($0.uuid) == c }) else { return nil }
        return (p, ch)
    }

    private func props(_ c: CBCharacteristic) -> [String: Bool] {
        [
            "read": c.properties.contains(.read),
            "write": c.properties.contains(.write),
            "writeWithoutResponse": c.properties.contains(.writeWithoutResponse),
            "notify": c.properties.contains(.notify),
            "indicate": c.properties.contains(.indicate)
        ]
    }

    /// Führt den Block aus, sobald Bluetooth bereit ist.
    private func ready(_ id: Int, _ block: @escaping () -> Void) {
        switch central.state {
        case .poweredOn:
            block()
        case .unknown, .resetting:
            stateWaiters.append { [weak self] in self?.ready(id, block) }
        case .poweredOff:
            fail(id, "Bluetooth ist ausgeschaltet.")
        case .unauthorized:
            fail(id, "Bluetooth-Zugriff nicht erlaubt. Bitte in den iOS-Einstellungen für diese App erlauben.")
        case .unsupported:
            fail(id, "Bluetooth LE wird auf diesem Gerät nicht unterstützt.")
        @unknown default:
            fail(id, "Bluetooth nicht verfügbar.")
        }
    }

    private func updateScan() {
        guard central.state == .poweredOn else { return }
        if pickerActive || !watchers.isEmpty {
            central.stopScan()
            central.scanForPeripherals(withServices: nil,
                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        } else {
            central.stopScan()
        }
    }

    // MARK: Befehle aus der Seite

    func handle(_ m: [String: Any]) {
        guard let id = m["id"] as? Int, let cmd = m["cmd"] as? String else { return }

        switch cmd {
        case "requestDevice":
            requestDevice(id)

        case "getDevices":
            ready(id) { [weak self] in
                guard let self = self else { return }
                let stored = self.known
                let ids = stored.compactMap { UUID(uuidString: $0["id"] ?? "") }
                let found = self.central.retrievePeripherals(withIdentifiers: ids)
                var out: [[String: String]] = []
                for p in found {
                    self.register(p)
                    let saved = stored.first { $0["id"] == p.identifier.uuidString }?["name"] ?? ""
                    out.append(["id": p.identifier.uuidString, "name": p.name ?? saved])
                }
                self.ok(id, out)
            }

        case "watch":
            guard let u = devUUID(m), periph(u) != nil else { fail(id, "Gerät unbekannt."); return }
            ready(id) { [weak self] in
                self?.watchers.insert(u)
                self?.updateScan()
                self?.ok(id)
            }

        case "unwatch":
            if let u = devUUID(m) { watchers.remove(u); updateScan() }
            ok(id)

        case "forget":
            if let u = devUUID(m) {
                known = known.filter { $0["id"] != u.uuidString }
                watchers.remove(u)
                if let p = peripherals[u], p.state != .disconnected { central.cancelPeripheralConnection(p) }
                updateScan()
            }
            ok(id)

        case "connect":
            guard let u = devUUID(m), let p = periph(u) else { fail(id, "Gerät unbekannt."); return }
            ready(id) { [weak self] in
                guard let self = self else { return }
                if p.state == .connected { self.connected.insert(u); self.ok(id); return }
                self.wait(self.key("conn", u), id)
                self.central.connect(p, options: nil)
                let w = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.central.cancelPeripheralConnection(p)
                    self.finish(self.key("conn", u), success: false, error: "Zeitüberschreitung beim Verbinden.")
                }
                self.connectTimers[u]?.cancel()
                self.connectTimers[u] = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: w)
            }

        case "disconnect":
            if let u = devUUID(m), let p = peripherals[u], p.state != .disconnected {
                central.cancelPeripheralConnection(p)
            }
            ok(id)

        case "service":
            guard let u = devUUID(m), let p = periph(u), let s = (m["svc"] as? String)?.lowercased() else {
                fail(id, "Ungültige Anfrage."); return
            }
            guard p.state == .connected else { fail(id, "GATT-Server nicht verbunden.", "NetworkError"); return }
            guard let cb = cbuuid(s) else { fail(id, "Ungültige UUID: \(s)", "SyntaxError"); return }
            if p.services?.contains(where: { norm($0.uuid) == s }) == true { ok(id); return }
            wait(key("svc", u, s), id)
            p.discoverServices([cb])

        case "characteristic":
            guard let u = devUUID(m), let p = periph(u),
                  let s = (m["svc"] as? String)?.lowercased(),
                  let c = (m["chr"] as? String)?.lowercased() else { fail(id, "Ungültige Anfrage."); return }
            guard p.state == .connected else { fail(id, "GATT-Server nicht verbunden."); return }
            guard let cb = cbuuid(c) else { fail(id, "Ungültige UUID: \(c)", "SyntaxError"); return }
            guard let service = p.services?.first(where: { norm($0.uuid) == s }) else {
                fail(id, "Service nicht gefunden.", "NotFoundError"); return
            }
            if let ch = service.characteristics?.first(where: { norm($0.uuid) == c }) { ok(id, props(ch)); return }
            wait(key("chr", u, s, c), id)
            p.discoverCharacteristics([cb], for: service)

        case "read":
            guard let (p, c) = lookup(m) else { fail(id, "Merkmal nicht gefunden.", "NotFoundError"); return }
            guard c.properties.contains(.read) else { fail(id, "Lesen nicht unterstützt.", "NotSupportedError"); return }
            wait(ckey("read", p, c), id)
            p.readValue(for: c)

        case "write":
            guard let (p, c) = lookup(m) else { fail(id, "Merkmal nicht gefunden.", "NotFoundError"); return }
            guard c.properties.contains(.write) else { fail(id, "Schreiben nicht unterstützt.", "NotSupportedError"); return }
            let data = Data(base64Encoded: m["value"] as? String ?? "") ?? Data()
            wait(ckey("write", p, c), id)
            p.writeValue(data, for: c, type: .withResponse)

        case "writeNoResponse":
            guard let (p, c) = lookup(m) else { fail(id, "Merkmal nicht gefunden.", "NotFoundError"); return }
            guard c.properties.contains(.writeWithoutResponse) else { fail(id, "Schreiben nicht unterstützt.", "NotSupportedError"); return }
            let data = Data(base64Encoded: m["value"] as? String ?? "") ?? Data()
            p.writeValue(data, for: c, type: .withoutResponse)
            ok(id)

        case "notify":
            guard let (p, c) = lookup(m) else { fail(id, "Merkmal nicht gefunden.", "NotFoundError"); return }
            guard c.properties.contains(.notify) || c.properties.contains(.indicate) else {
                fail(id, "Benachrichtigungen nicht unterstützt.", "NotSupportedError"); return
            }
            wait(ckey("notify", p, c), id)
            p.setNotifyValue((m["on"] as? Bool) ?? true, for: c)

        default:
            fail(id, "Unbekannter Befehl: \(cmd)")
        }
    }

    private func requestDevice(_ id: Int) {
        ready(id) { [weak self] in
            guard let self = self, let host = self.host else { return }
            if self.picker != nil { self.fail(id, "Auswahl läuft bereits.", "InvalidStateError"); return }

            let pk = DevicePicker()
            self.picker = pk
            pk.onDone = { [weak self] p in
                guard let self = self else { return }
                self.picker = nil
                self.pickerActive = false
                self.updateScan()
                if let p = p {
                    self.register(p)
                    let name = p.name ?? self.advNames[p.identifier] ?? ""
                    self.remember(p.identifier, name)
                    self.ok(id, ["id": p.identifier.uuidString, "name": name])
                } else {
                    self.fail(id, "User cancelled the requestDevice() chooser.", "NotFoundError")
                }
            }
            self.pickerActive = true
            self.updateScan()

            let nav = UINavigationController(rootViewController: pk)
            nav.overrideUserInterfaceStyle = .dark
            nav.presentationController?.delegate = pk
            host.present(nav, animated: true)
        }
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .unknown && central.state != .resetting {
            let w = stateWaiters
            stateWaiters = []
            w.forEach { $0() }
        }
        if central.state == .poweredOn {
            updateScan()
        } else if central.state == .poweredOff {
            for u in connected { emit("disconnected", ["dev": u.uuidString]) }
            connected.removeAll()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        register(peripheral)
        let adName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        if let n = adName { advNames[peripheral.identifier] = n }
        picker?.update(peripheral, name: peripheral.name ?? adName, rssi: RSSI.intValue)

        if watchers.contains(peripheral.identifier) {
            watchers.remove(peripheral.identifier)
            updateScan()
            emit("adv", ["dev": peripheral.identifier.uuidString])
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let u = peripheral.identifier
        connectTimers[u]?.cancel()
        connectTimers[u] = nil
        connected.insert(u)
        finish(key("conn", u), success: true)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let u = peripheral.identifier
        connectTimers[u]?.cancel()
        connectTimers[u] = nil
        finish(key("conn", u), success: false, error: error?.localizedDescription ?? "Verbindung fehlgeschlagen.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let u = peripheral.identifier
        connectTimers[u]?.cancel()
        connectTimers[u] = nil
        connected.remove(u)
        failAll(for: u, "GATT-Server getrennt.")
        emit("disconnected", ["dev": u.uuidString])
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        let prefix = "svc|\(p.identifier.uuidString)|"
        for k in Array(waiters.keys) where k.hasPrefix(prefix) {
            let s = String(k.dropFirst(prefix.count))
            if p.services?.contains(where: { norm($0.uuid) == s }) == true {
                finish(k, success: true)
            } else {
                finish(k, success: false, error: "Service \(s) nicht gefunden.", name: "NotFoundError")
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let prefix = "chr|\(p.identifier.uuidString)|\(norm(service.uuid))|"
        for k in Array(waiters.keys) where k.hasPrefix(prefix) {
            let c = String(k.dropFirst(prefix.count))
            if let ch = service.characteristics?.first(where: { norm($0.uuid) == c }) {
                finish(k, success: true, payload: props(ch))
            } else {
                finish(k, success: false, error: "Merkmal \(c) nicht gefunden.", name: "NotFoundError")
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        let k = ckey("read", p, c)
        if waiters[k] != nil {
            if let e = error {
                finish(k, success: false, error: e.localizedDescription)
            } else {
                finish(k, success: true, payload: ["value": (c.value ?? Data()).base64EncodedString()])
            }
            return
        }
        guard error == nil, let v = c.value else { return }
        let s: CBService? = c.service
        emit("value", [
            "dev": p.identifier.uuidString,
            "svc": s.map { norm($0.uuid) } ?? "",
            "chr": norm(c.uuid),
            "value": v.base64EncodedString()
        ])
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        let k = ckey("write", p, c)
        if let e = error { finish(k, success: false, error: e.localizedDescription) }
        else { finish(k, success: true) }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        let k = ckey("notify", p, c)
        if let e = error { finish(k, success: false, error: e.localizedDescription) }
        else { finish(k, success: true) }
    }
}
