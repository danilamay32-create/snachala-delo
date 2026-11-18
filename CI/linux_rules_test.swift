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

print(failed.isEmpty ? "ALL PASSED" : "FAILED: \(failed)")
exit(failed.isEmpty ? 0 : 1)
