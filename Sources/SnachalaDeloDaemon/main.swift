import Foundation
import Darwin
import Shared

// Фоновая служба «Сначала дело». Запускается launchd от root при старте Мака.
// Держит задачи, проверяет правила, правит /etc/hosts, фильтрует DNS и закрывает плееры.

if CommandLine.arguments.contains("--cleanup") {
    // Вызывается из скрипта удаления: снять блокировку сайтов и вернуть прежний DNS.
    HostsBlocker.apply(sites: nil)
    let s = Store()
    if let b = s.state.dnsBackup {
        DNSSwitch.disable(backup: b)
        s.setDNSBackup(nil)
    }
    exit(0)
}

guard getuid() == 0 else {
    log("must run as root")
    exit(1)
}

signal(SIGPIPE, SIG_IGN)

let queue = DispatchQueue(label: "ru.snachaladelo.daemon")
let store = Store()
let killer = AppKiller()
let dns = DNSFilter()
let dnsReady = dns.start()

// MARK: Enforcement loop

var lastHostsCheck = Date.distantPast
var lastLocked: Bool?
var lastSites: [String] = []

func enforce(force: Bool = false) {
    let now = Date()
    if store.tick(now) { store.save() }
    let locked = store.isLocked(now)
    let sites = store.state.sites
    // Файл hosts проверяем раз в 10 секунд (вдруг его поправили руками) или сразу при изменении.
    if force || locked != lastLocked || sites != lastSites || now.timeIntervalSince(lastHostsCheck) > 10 {
        HostsBlocker.apply(sites: locked ? sites : nil)
        applyDNS(locked: locked, sites: sites)
        lastHostsCheck = now
        lastLocked = locked
        lastSites = sites
    }
    if locked {
        killer.enforce(blocked: Set(store.state.apps.map(\.bundleID)))
    }
}

/// Пока блокирует — DNS Мака смотрит на наш фильтр; иначе — прежние настройки.
func applyDNS(locked: Bool, sites: [String]) {
    dns.sites = sites
    if locked && dnsReady {
        DNSSwitch.enable(backup: store.state.dnsBackup) { store.setDNSBackup($0) }
        dns.backupServers = (store.state.dnsBackup ?? [:]).values.flatMap { $0 }
    } else if let b = store.state.dnsBackup {
        DNSSwitch.disable(backup: b)
        store.setDNSBackup(nil)
    }
}

// Если службу останавливают (выключение Мака, удаление, обновление) — вернуть DNS,
// чтобы интернет не остался без адресов. При старте фильтр включится снова.
signal(SIGTERM, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
termSource.setEventHandler {
    if let b = store.state.dnsBackup {
        DNSSwitch.disable(backup: b)
        store.setDNSBackup(nil)
    }
    log("stopped")
    exit(0)
}
termSource.resume()

let timer = DispatchSource.makeTimerSource(queue: queue)
timer.schedule(deadline: .now(), repeating: .seconds(2))
timer.setEventHandler { enforce() }
timer.resume()

// MARK: Socket server

func startServer() {
    unlink(Paths.socket)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { log("socket() failed"); exit(1) }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(Paths.socket.utf8)
    withUnsafeMutableBytes(of: &addr.sun_path) { buf in
        for (i, b) in bytes.prefix(buf.count - 1).enumerated() { buf[i] = b }
    }
    let bound = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard bound == 0 else { log("bind() failed: \(errno)"); exit(1) }
    // Подключаться может любой пользователь Мака: все правила проверяет служба.
    chmod(Paths.socket, 0o666)
    guard listen(fd, 16) == 0 else { log("listen() failed"); exit(1) }

    let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    src.setEventHandler {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }
        IPC.setTimeout(client, seconds: 2)
        let resp: Response
        if let line = IPC.readLine(client), let req = try? IPC.decoder.decode(Request.self, from: line) {
            resp = store.handle(req)
            if req.cmd != .state { enforce(force: true) }
        } else {
            resp = Response(error: "Плохой запрос")
        }
        if let data = try? IPC.encoder.encode(resp) { _ = IPC.writeAll(client, data) }
    }
    src.resume()
    // держим ссылку
    serverSource = src
}

var serverSource: DispatchSourceRead?
queue.sync { startServer() }
log("started")
dispatchMain()
