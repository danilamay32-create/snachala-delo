import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Простой протокол поверх Unix-сокета: одна JSON-строка запроса, одна JSON-строка ответа.
public enum IPC {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    static func makeAddr(_ path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in bytes.prefix(buf.count - 1).enumerated() { buf[i] = b }
        }
        return addr
    }

    public static func setTimeout(_ fd: Int32, seconds: Int) {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Читает до перевода строки или конца потока.
    public static func readLine(_ fd: Int32, limit: Int = 4 << 20) -> Data? {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count < limit {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
            if buf[0..<n].contains(10) { break }
        }
        if let nl = data.firstIndex(of: 10) { data = data[..<nl] }
        return data.isEmpty ? nil : data
    }

    public static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        var payload = data
        payload.append(10)
        return payload.withUnsafeBytes { raw -> Bool in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: off), raw.count - off)
                if n <= 0 { return false }
                off += n
            }
            return true
        }
    }

    public enum ClientError: Error { case connect, io, decode }

    /// Синхронный запрос к службе. Вызывать не с главного потока.
    public static func send(_ req: Request, path: String = Paths.socket) throws -> Response {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ClientError.connect }
        defer { close(fd) }
        setTimeout(fd, seconds: 3)
        var addr = makeAddr(path)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard ok == 0 else { throw ClientError.connect }
        guard writeAll(fd, try encoder.encode(req)) else { throw ClientError.io }
        guard let line = readLine(fd) else { throw ClientError.io }
        guard let resp = try? decoder.decode(Response.self, from: line) else { throw ClientError.decode }
        return resp
    }
}
