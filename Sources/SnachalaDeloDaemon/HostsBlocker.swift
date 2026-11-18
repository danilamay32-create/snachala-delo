import Foundation
import Shared

/// Блокирует сайты через собственный раздел в /etc/hosts. Работает во всех браузерах.
enum HostsBlocker {
    static let begin = "# >>> Сначала дело: не редактировать вручную"
    static let end = "# <<< Сначала дело"

    static func expand(_ sites: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for s in sites {
            for h in [s, "www." + s, "m." + s] where seen.insert(h).inserted {
                out.append(h)
            }
        }
        return out
    }

    static func strip(_ text: String) -> String {
        var lines: [Substring] = []
        var inside = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("# >>> Сначала дело") { inside = true; continue }
            if line.hasPrefix(end) { inside = false; continue }
            if !inside { lines.append(line) }
        }
        var result = lines.joined(separator: "\n")
        while result.hasSuffix("\n\n") { result.removeLast() }
        if !result.hasSuffix("\n") { result += "\n" }
        return result
    }

    static func render(base: String, sites: [String]?) -> String {
        guard let sites = sites, !sites.isEmpty else { return base }
        var s = base + begin + "\n"
        for h in expand(sites) {
            s += "0.0.0.0 \(h)\n:: \(h)\n"
        }
        s += end + "\n"
        return s
    }

    /// sites == nil снимает блокировку. Пишет файл, только если он реально отличается.
    @discardableResult
    static func apply(sites: [String]?, path: String = Paths.hosts) -> Bool {
        let current = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let wanted = render(base: strip(current), sites: sites)
        guard wanted != current else { return false }
        do {
            try wanted.write(toFile: path, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o644, .ownerAccountID: 0, .groupOwnerAccountID: 0],
                                                   ofItemAtPath: path)
            flushDNS()
            log(sites == nil ? "sites unblocked" : "sites blocked (\(sites!.count))")
            return true
        } catch {
            log("hosts write failed: \(error)")
            return false
        }
    }

    static func flushDNS() {
        run("/usr/bin/dscacheutil", ["-flushcache"])
        run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
    }

    static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}
