import UIKit
import CoreBluetooth

/// Geräteauswahl als Ersatz für den Chrome-Dialog von requestDevice().
final class DevicePicker: UITableViewController, UIAdaptivePresentationControllerDelegate {

    struct Entry {
        let peripheral: CBPeripheral
        var name: String?
        var rssi: Int
    }

    var onDone: ((CBPeripheral?) -> Void)?

    private var entries: [UUID: Entry] = [:]
    private var list: [Entry] = []
    private var signature = ""
    private var timer: Timer?
    private var finished = false

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit { timer?.invalidate() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Roller auswählen"
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 10 / 255, green: 18 / 255, blue: 48 / 255, alpha: 1)
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func update(_ p: CBPeripheral, name: String?, rssi: Int) {
        entries[p.identifier] = Entry(peripheral: p, name: name, rssi: rssi)
    }

    private func refresh() {
        let sorted = entries.values.sorted { a, b in
            let an = a.name != nil, bn = b.name != nil
            if an != bn { return an }
            if let x = a.name, let y = b.name, x != y { return x.lowercased() < y.lowercased() }
            return a.peripheral.identifier.uuidString < b.peripheral.identifier.uuidString
        }
        let sig = sorted.map { $0.peripheral.identifier.uuidString + ($0.name ?? "") }.joined(separator: ",")
        guard sig != signature else { return }
        signature = sig
        list = sorted
        tableView.reloadData()
    }

    @objc private func cancelTapped() { finish(nil) }

    private func finish(_ p: CBPeripheral?) {
        guard !finished else { return }
        finished = true
        timer?.invalidate()
        let done = onDone
        if let nav = navigationController {
            nav.dismiss(animated: true) { done?(p) }
        } else {
            done?(p)
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard !finished else { return }
        finished = true
        timer?.invalidate()
        onDone?(nil)
    }

    // MARK: Tabelle

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { list.count }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        list.isEmpty ? "Suche läuft … Roller einschalten und in der Nähe halten." : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let e = list[indexPath.row]
        cell.textLabel?.text = e.name ?? "Unbekanntes Gerät"
        cell.detailTextLabel?.text = "Signal \(e.rssi) dBm · \(e.peripheral.identifier.uuidString.prefix(8))"
        cell.backgroundColor = UIColor(white: 1, alpha: 0.07)
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = UIColor(red: 0.56, green: 0.61, blue: 0.77, alpha: 1)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        finish(list[indexPath.row].peripheral)
    }
}
