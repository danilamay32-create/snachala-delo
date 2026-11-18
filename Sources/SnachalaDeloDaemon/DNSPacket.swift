import Foundation

/// Минимальный разбор DNS-запроса: только то, что нужно фильтру.
struct DNSQuery {
    let id: UInt16
    let flags: UInt16
    let name: String
    let qtype: UInt16
    /// Байты секции вопроса (имя + тип + класс), чтобы вернуть её в ответе как есть.
    let question: Data

    init?(_ packet: Data) {
        let b = [UInt8](packet)
        guard b.count >= 17 else { return nil }
        id = UInt16(b[0]) << 8 | UInt16(b[1])
        flags = UInt16(b[2]) << 8 | UInt16(b[3])
        let qd = UInt16(b[4]) << 8 | UInt16(b[5])
        guard flags & 0x8000 == 0, qd >= 1 else { return nil }   // это запрос и в нём есть вопрос
        var i = 12
        var labels: [String] = []
        while true {
            guard i < b.count else { return nil }
            let len = Int(b[i])
            if len == 0 { i += 1; break }
            guard len & 0xC0 == 0, i + 1 + len <= b.count, labels.count < 64 else { return nil }
            labels.append(String(decoding: b[(i + 1)..<(i + 1 + len)], as: UTF8.self))
            i += 1 + len
        }
        guard i + 4 <= b.count else { return nil }
        qtype = UInt16(b[i]) << 8 | UInt16(b[i + 1])
        name = labels.joined(separator: ".").lowercased()
        question = Data(b[12..<(i + 4)])
    }

    /// Ответ «сайт по адресу 0.0.0.0 / ::» для A/AAAA и пустой ответ для остальных типов.
    func blockedResponse() -> Data {
        var out = Data()
        func u16(_ v: UInt16) { out.append(UInt8(v >> 8)); out.append(UInt8(v & 0xFF)) }
        let answer = qtype == 1 || qtype == 28
        u16(id)
        u16(0x8000 | (flags & 0x7900) | 0x0080)   // QR, тот же opcode и RD, RA, без ошибки
        u16(1)                                     // вопросов
        u16(answer ? 1 : 0)                        // ответов
        u16(0); u16(0)
        out.append(question)
        if answer {
            u16(0xC00C)                            // ссылка на имя из вопроса
            u16(qtype)
            u16(1)                                 // класс IN
            u16(0); u16(60)                        // TTL 60 с
            let len: UInt16 = qtype == 1 ? 4 : 16
            u16(len)
            out.append(Data(repeating: 0, count: Int(len)))
        }
        return out
    }

    /// Собирает простой запрос (для тестов и проверки апстрима).
    static func make(name: String, qtype: UInt16, id: UInt16 = 0x1234) -> Data {
        var out = Data()
        func u16(_ v: UInt16) { out.append(UInt8(v >> 8)); out.append(UInt8(v & 0xFF)) }
        u16(id); u16(0x0100); u16(1); u16(0); u16(0); u16(0)
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8)
            out.append(UInt8(bytes.count))
            out.append(contentsOf: bytes)
        }
        out.append(0)
        u16(qtype); u16(1)
        return out
    }
}
