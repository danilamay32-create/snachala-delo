// Проверка правил службы и правки /etc/hosts на Linux (без AppKit/Darwin-частей).
import Foundation
import Shared

var failed: [String] = []
func check(_ name: String, _ cond: Bool) {
    print((cond ? "PASS " : "FAIL ") + name)
    if !cond { failed.append(name) }
}

let now = Date()
let store = Store()
func snap() -> Snapshot { store.snapshot(now) }

check("пусто — не блокирует", !snap().locked)
var r = store.handle(Request(.add, title: "Реферат", date: now.addingTimeInterval(7200)), now: now)
check("добавление ок", r.error == nil)
check("блокирует", r.snapshot!.locked)
check("пустое название отклонено", store.handle(Request(.add, title: " ", date: now.addingTimeInterval(60)), now: now).error != nil)
check("прошедший дедлайн отклонён", store.handle(Request(.add, title: "x", date: now.addingTimeInterval(-5)), now: now).error != nil)
check("удалить сайт нельзя", store.handle(Request(.removeSite, site: "youtube.com"), now: now).error != nil)
r = store.handle(Request(.addSite, site: "HTTPS://www.Foo-Bar.ru/path?q"), now: now)
check("нормализация сайта", r.snapshot!.sites.contains("foo-bar.ru"))
check("мусор вместо сайта отклонён", store.handle(Request(.addSite, site: "просто текст"), now: now).error != nil)

let id = r.snapshot!.tasks.first { $0.title == "Реферат" }!.id
r = store.handle(Request(.reschedule, id: id, date: now.addingTimeInterval(3 * 86400)), now: now)
check("первый перенос ок", r.error == nil && !r.snapshot!.locked)
r = store.handle(Request(.reschedule, id: id, date: now.addingTimeInterval(5 * 86400)), now: now)
check("второй далёкий перенос запрещён", r.error != nil)
r = store.handle(Request(.reschedule, id: id, date: now.addingTimeInterval(20 * 3600)), now: now)
check("сдвиг раньше ок и блокирует", r.error == nil && r.snapshot!.locked)

r = store.handle(Request(.startPass), now: now)
check("передышка", r.error == nil && !r.snapshot!.locked && !r.snapshot!.passAvailableToday)
let later = now.addingTimeInterval(16 * 60)
_ = store.tick(later)
check("после 15 минут снова блокирует", store.snapshot(later).locked)
check("вторая передышка за день запрещена", store.handle(Request(.startPass), now: later).error != nil)

r = store.handle(Request(.requestDelete, id: id), now: later)
check("удаление отложено", r.snapshot!.tasks.first { $0.id == id }?.deleteAt != nil)
_ = store.tick(later.addingTimeInterval(10))
check("через 10 с ещё на месте", store.snapshot(later).tasks.contains { $0.id == id })
_ = store.tick(later.addingTimeInterval(31))
check("через 31 с удалено", !store.snapshot(later).tasks.contains { $0.id == id })

r = store.handle(Request(.add, title: "Просрочка", date: now.addingTimeInterval(60)), now: now)
let overdueAt = now.addingTimeInterval(3600)
check("просроченная блокирует", store.snapshot(overdueAt).locked)
let oid = r.snapshot!.tasks.first { $0.title == "Просрочка" }!.id
r = store.handle(Request(.complete, id: oid), now: overdueAt)
check("закрытие снимает блокировку", !r.snapshot!.locked)
check("удаление закрытой — сразу", store.handle(Request(.requestDelete, id: oid), now: overdueAt).snapshot!.tasks.isEmpty)

// hosts
let tmp = NSTemporaryDirectory() + "hosts-test"
let original = "127.0.0.1 localhost\n255.255.255.255 broadcasthost\n"
try! original.write(toFile: tmp, atomically: true, encoding: .utf8)
HostsBlocker.apply(sites: ["youtube.com"], path: tmp)
let blocked = try! String(contentsOfFile: tmp, encoding: .utf8)
check("hosts: youtube заблокирован", blocked.contains("0.0.0.0 youtube.com\n") && blocked.contains(":: www.youtube.com\n"))
check("hosts: старые строки на месте", blocked.hasPrefix(original))
HostsBlocker.apply(sites: ["youtube.com"], path: tmp)
check("hosts: повторно не дублирует", (try! String(contentsOfFile: tmp, encoding: .utf8)) == blocked)
HostsBlocker.apply(sites: nil, path: tmp)
check("hosts: снятие возвращает как было", (try! String(contentsOfFile: tmp, encoding: .utf8)) == original)

// слова и зеркала
let sites = ["youtube.com", "lordfilm", "rezka"]
check("зеркало lordfilm по слову", Defaults.isBlocked(host: "lordfilm-2026.xyz", sites: sites))
check("поддомен зеркала", Defaults.isBlocked(host: "www.Hd.LordFilm.cc.", sites: sites))
check("hdrezka по слову rezka", Defaults.isBlocked(host: "hdrezka-home.tv", sites: sites))
check("поддомен youtube", Defaults.isBlocked(host: "m.youtube.com", sites: sites))
check("google не задет", !Defaults.isBlocked(host: "www.google.com", sites: sites))
check("похожий домен не задет", !Defaults.isBlocked(host: "notyoutube.com", sites: sites))
check("слово из ввода", Defaults.normalizeSite("  LordFilm ") == "lordfilm")
check("короткое слово отклонено", Defaults.normalizeSite("kin") == nil)
check("в hosts слова не попадают", !HostsBlocker.expand(["lordfilm", "ivi.ru"]).contains("lordfilm"))
check("список по умолчанию содержит lordfilm", Defaults.sites.contains("lordfilm"))

// DNS-пакеты
let qA = DNSQuery.make(name: "LordFilm-Zerkalo.com", qtype: 1, id: 0xBEEF)
let parsed = DNSQuery(qA)
check("разбор запроса", parsed?.name == "lordfilm-zerkalo.com" && parsed?.qtype == 1 && parsed?.id == 0xBEEF)
let respA = [UInt8](parsed!.blockedResponse())
check("ответ: тот же id и флаг ответа", respA[0] == 0xBE && respA[1] == 0xEF && respA[2] & 0x80 != 0)
check("ответ: одна запись A 0.0.0.0", respA[7] == 1 && Array(respA.suffix(4)) == [0, 0, 0, 0] && respA.count == qA.count + 16)
let qAAAA = DNSQuery(DNSQuery.make(name: "rezka.ag", qtype: 28))!
let respAAAA = [UInt8](qAAAA.blockedResponse())
check("ответ AAAA: ::", respAAAA[7] == 1 && respAAAA.suffix(16).allSatisfy { $0 == 0 })
let qHTTPS = DNSQuery(DNSQuery.make(name: "rezka.ag", qtype: 65))!
check("ответ HTTPS-записи пустой", [UInt8](qHTTPS.blockedResponse())[7] == 0)
check("мусор не разбирается", DNSQuery(Data([1, 2, 3])) == nil)

// обновление старых настроек: новые слова добавляются, свои сайты остаются
let migr = Store()
migr.handle(Request(.addSite, site: "my-serial.ru"), now: now)
check("после миграции есть lordfilm и свой сайт",
      migr.state.sites.contains("lordfilm") && migr.state.sites.contains("my-serial.ru"))

print(failed.isEmpty ? "ALL PASSED" : "FAILED: \(failed)")
exit(failed.isEmpty ? 0 : 1)
