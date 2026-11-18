import Foundation
import Darwin
import Shared

/// Локальный DNS-сервер на 127.0.0.1:53. Пока блокировка включена, Мак спрашивает адреса сайтов
/// у него: заблокированным (в том числе любым зеркалам по слову) он отвечает «0.0.0.0»,
/// остальные запросы честно пересылает обычному DNS.
final class DNSFilter {
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private let work = DispatchQueue(label: "ru.snachaladelo.dns", attributes: .concurrent)
    private let lock = NSLock()
    private var _sites: [String] = []
    private var _upstream: [String] = []
    private var upstreamCheckedAt = Date.distantPast

    var sites: [String] {
        get { lock.lock(); defer { lock.unlock() }; return _sites }
        set { lock.lock(); _sites = newValue; lock.unlock() }
    }

    var isRunning: Bool { fd >= 0 }

    /// Слушать 127.0.0.1:port. false — порт занят (например, другим DNS-сервером), тогда фильтр не включаем.
    func start(port: UInt16 = 53) -> Bool {
        let s = socket(AF_INET, SOCK_DGRAM, 0)
        guard s >= 0 else { return false }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard ok == 0 else { close(s); log("dns: bind 127.0.0.1:\(port) failed, errno \(errno)"); return false }
        fd = s
        let src = DispatchSource.makeReadSource(fileDescriptor: s, queue: work)
        src.setEventHandler { [weak self] in self?.receive() }
        src.resume()
        source = src
        log("dns: listening on 127.0.0.1:\(port)")
        return true
    }

    private func receive() {
        var buf = [UInt8](repeating: 0, count: 4096)
        var from = sockaddr_storage()
        var fromLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let n = withUnsafeMutablePointer(to: &from) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(fd, &buf, buf.count, 0, $0, &fromLen)
            }
        }
        guard n > 0 else { return }
        let packet = Data(buf[0..<n])
        let client = from
        let clientLen = fromLen
        work.async { [weak self] in self?.handle(packet, client: client, clientLen: clientLen) }
    }

    private func handle(_ packet: Data, client: sockaddr_storage, clientLen: socklen_t) {
        let reply: Data?
        if let q = DNSQuery(packet), Defaults.isBlocked(host: q.name, sites: sites) {
            reply = q.blockedResponse()
        } else {
            reply = forward(packet)
        }
        guard let r = reply else { return }
        var c = client
        _ = r.withUnsafeBytes { raw in
            withUnsafePointer(to: &c) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, raw.baseAddress, raw.count, 0, $0, clientLen)
                }
            }
        }
    }

    // MARK: Upstream

    /// Настоящие DNS-серверы: из DHCP текущей сети, затем прежние ручные, затем запасные.
    private var _backupServers: [String] = []
    var backupServers: [String] {
        get { lock.lock(); defer { lock.unlock() }; return _backupServers }
        set { lock.lock(); _backupServers = newValue; lock.unlock() }
    }

    private func upstream() -> [String] {
        lock.lock()
        let fresh = Date().timeIntervalSince(upstreamCheckedAt) < 30
        let cached = _upstream
        lock.unlock()
        if fresh && !cached.isEmpty { return cached }
        var list = DNSSwitch.dhcpServers()
        list += backupServers
        list += ["77.88.8.8", "1.1.1.1", "8.8.8.8"]
        var seen = Set<String>()
        list = list.filter { $0 != "127.0.0.1" && $0 != "::1" && !$0.contains(":") && seen.insert($0).inserted }
        lock.lock(); _upstream = list; upstreamCheckedAt = Date(); lock.unlock()
        return list
    }

    private func forward(_ packet: Data) -> Data? {
        for server in upstream() {
            if let r = DNSFilter.ask(server, packet, timeout: 2) { return r }
        }
        return nil
    }

    static func ask(_ server: String, _ packet: Data, timeout: Int) -> Data? {
        let s = socket(AF_INET, SOCK_DGRAM, 0)
        guard s >= 0 else { return nil }
        defer { close(s) }
        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(53).bigEndian
        guard inet_pton(AF_INET, server, &addr.sin_addr) == 1 else { return nil }
        let sent = packet.withUnsafeBytes { raw in
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(s, raw.baseAddress, raw.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else { return nil }
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = recv(s, &buf, buf.count, 0)
        guard n >= 12, buf[0] == [UInt8](packet)[0], buf[1] == [UInt8](packet)[1] else { return nil }
        return Data(buf[0..<n])
    }
}

/// Переключение DNS у сетевых служб Мака (Wi-Fi, Ethernet…) на 127.0.0.1 и обратно.
enum DNSSwitch {
    static let networksetup = "/usr/sbin/networksetup"

    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    static func isIP(_ s: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        return inet_pton(AF_INET, s, &v4) == 1 || inet_pton(AF_INET6, s, &v6) == 1
    }

    /// Включённые сетевые службы (строки со «*» в начале — выключенные).
    static func services() -> [String] {
        run(networksetup, ["-listallnetworkservices"])
            .split(separator: "\n").dropFirst()
            .map(String.init)
            .filter { !$0.hasPrefix("*") && !$0.isEmpty }
    }

    static func servers(of service: String) -> [String] {
        run(networksetup, ["-getdnsservers", service])
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter(isIP)
    }

    static func set(_ service: String, _ servers: [String]) {
        _ = run(networksetup, ["-setdnsservers", service] + (servers.isEmpty ? ["Empty"] : servers))
    }

    /// DNS, который выдала текущая сеть по DHCP (работает, даже когда вручную стоит 127.0.0.1).
    static func dhcpServers() -> [String] {
        let route = run("/sbin/route", ["-n", "get", "default"])
        guard let line = route.split(separator: "\n").first(where: { $0.contains("interface:") }),
              let iface = line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) else { return [] }
        let out = run("/usr/sbin/ipconfig", ["getoption", iface, "domain_name_server"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return isIP(out) ? [out] : []
    }

    /// Включить фильтр. Возвращает резервную копию прежних настроек (её надо сохранить до переключения).
    static func enable(backup: [String: [String]]?, save: ([String: [String]]) -> Void) {
        var b = backup ?? [:]
        let svcs = services()
        var changed = false
        for s in svcs where b[s] == nil {
            b[s] = servers(of: s).filter { $0 != "127.0.0.1" }
            changed = true
        }
        if changed || backup == nil { save(b) }
        var switched = false
        for s in svcs where servers(of: s) != ["127.0.0.1"] {
            set(s, ["127.0.0.1"])
            switched = true
        }
        if switched {
            HostsBlocker.flushDNS()
            log("dns: filter on (\(svcs.joined(separator: ", ")))")
        }
    }

    /// Вернуть прежние настройки DNS.
    static func disable(backup: [String: [String]]) {
        let svcs = Set(services())
        for (s, servers) in backup where svcs.contains(s) {
            set(s, servers)
        }
        HostsBlocker.flushDNS()
        log("dns: filter off, settings restored")
    }
}
