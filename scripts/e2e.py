"""Сквозной тест установленной службы через её сокет. Запускать от root."""
import functools, json, os, socket, subprocess, sys, time
print = functools.partial(print, flush=True)

SOCK = "/var/run/ru.snachaladelo.sock"
failures = []

def call(cmd, **kw):
    req = {"cmd": cmd, **kw}
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(SOCK)
    s.sendall((json.dumps(req) + "\n").encode())
    data = b""
    while not data.endswith(b"\n"):
        chunk = s.recv(65536)
        if not chunk:
            break
        data += chunk
    s.close()
    return json.loads(data)

def check(name, cond, extra=""):
    print(("PASS " if cond else "FAIL ") + name + (f"  [{extra}]" if extra and not cond else ""))
    if not cond:
        failures.append(name)

def hosts():
    return open("/private/etc/hosts").read()

def resolves_blocked(host):
    try:
        out = subprocess.run(["dscacheutil", "-q", "host", "-a", "name", host],
                             capture_output=True, text=True, timeout=10).stdout
    except Exception as e:
        return f"error {e}"
    return out

def task(snap, title):
    return next((t for t in snap["tasks"] if t["title"] == title), None)

now = time.time()

# 1. служба жива
for _ in range(30):
    if os.path.exists(SOCK):
        break
    time.sleep(1)
r = call("state")
snap = r["snapshot"]
check("служба отвечает", snap is not None)
check("изначально не блокирует", snap["locked"] is False, snap)
check("в списке есть youtube.com", "youtube.com" in snap["sites"])

# 2. задача через 2 часа включает блокировку
r = call("add", title="Реферат", date=now + 2 * 3600)
check("добавление без ошибки", r.get("error") is None, r.get("error"))
check("заблокировано", r["snapshot"]["locked"] is True)
time.sleep(1)
h = hosts()
check("youtube.com в /etc/hosts", "0.0.0.0 youtube.com" in h and ":: www.youtube.com" in h)
check("google.com не тронут", "google.com" not in h.replace("googlevideo.com", ""))
res = resolves_blocked("www.youtube.com")
check("www.youtube.com резолвится в 0.0.0.0", "0.0.0.0" in res, res)
res = resolves_blocked("www.google.com")
check("www.google.com резолвится нормально", "0.0.0.0" not in res and "ip_address" in res, res)

# 3. пустое название и прошедший дедлайн
check("пустая задача отклонена", call("add", title="  ", date=now + 3600).get("error") is not None)
check("прошедший дедлайн отклонён", call("add", title="x", date=now - 60).get("error") is not None)

# 4. убрать сайт/приложение из списка нельзя, пока блокирует
check("удаление сайта запрещено", call("removeSite", site="youtube.com").get("error") is not None)
check("удаление приложения запрещено",
      call("removeApp", app={"bundleID": "org.videolan.vlc", "name": "VLC"}).get("error") is not None)
r = call("addSite", site="https://www.Example-Serial.com/watch?x=1")
check("добавление сайта с нормализацией", "example-serial.com" in r["snapshot"]["sites"], r)

# 5. запрещённое приложение закрывается
app = "/tmp/FakeVLC.app"
os.makedirs(app + "/Contents/MacOS", exist_ok=True)
with open("/tmp/fakevlc.c", "w") as f:
    f.write("#include <unistd.h>\nint main(void){ sleep(300); return 0; }\n")
subprocess.run(["cc", "-o", app + "/Contents/MacOS/FakeVLC", "/tmp/fakevlc.c"], check=True)
with open(app + "/Contents/Info.plist", "w") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>'
            '<key>CFBundleIdentifier</key><string>org.videolan.vlc</string>'
            '<key>CFBundleExecutable</key><string>FakeVLC</string></dict></plist>')
subprocess.run(["codesign", "--force", "--sign", "-", app], check=True)
log_before = open("/var/log/snachaladelo.log").read().count("closed: FakeVLC.app")
p = subprocess.Popen([app + "/Contents/MacOS/FakeVLC"])
time.sleep(7)
log_after = open("/var/log/snachaladelo.log").read().count("closed: FakeVLC.app")
check("плеер закрыт службой", p.poll() is not None and log_after > log_before,
      f"exit={p.poll()} log {log_before}->{log_after}")

# 6. закрытие задачи снимает блокировку
t = task(call("state")["snapshot"], "Реферат")
r = call("complete", id=t["id"])
check("после закрытия не блокирует", r["snapshot"]["locked"] is False)
time.sleep(1)
check("hosts очищен", "youtube.com" not in hosts())
p = subprocess.Popen([app + "/Contents/MacOS/FakeVLC"])
time.sleep(5)
check("без блокировки плеер работает", p.poll() is None)
p.kill()

# 7. удаление с паузой
r = call("add", title="Курсовая", date=now + 2 * 3600)
t = task(r["snapshot"], "Курсовая")
r = call("requestDelete", id=t["id"])
t2 = task(r["snapshot"], "Курсовая")
check("удаление отложено ~30 с", t2 and t2.get("deleteAt") and 25 < t2["deleteAt"] - time.time() <= 31, t2)
r = call("cancelDelete", id=t["id"])
check("удаление отменено", task(r["snapshot"], "Курсовая").get("deleteAt") is None)

# 8. переносы
r = call("reschedule", id=t["id"], date=now + 3 * 86400)
check("первый перенос на 3 дня разрешён", r.get("error") is None, r.get("error"))
check("после переноса не блокирует", r["snapshot"]["locked"] is False)
r = call("reschedule", id=t["id"], date=now + 5 * 86400)
check("второй перенос дальше суток запрещён", r.get("error") is not None)
r = call("reschedule", id=t["id"], date=now + 3 * 3600)
check("сдвиг раньше разрешён", r.get("error") is None, r.get("error"))
check("снова блокирует", r["snapshot"]["locked"] is True)

# 9. передышка
r = call("startPass")
check("передышка включилась", r.get("error") is None and r["snapshot"]["locked"] is False, r.get("error"))
check("передышка сегодня использована", r["snapshot"]["passAvailableToday"] is False)
time.sleep(1)
check("во время передышки hosts чист", "youtube.com" not in hosts())

# 10. перезапуск службы сохраняет задачи
subprocess.run(["launchctl", "kickstart", "-k", "system/ru.snachaladelo.daemon"], check=True)
time.sleep(3)
for _ in range(10):
    try:
        snap = call("state")["snapshot"]
        break
    except Exception:
        time.sleep(1)
check("задачи пережили перезапуск", task(snap, "Курсовая") is not None)
check("передышка пережила перезапуск", snap["passAvailableToday"] is False)

# 11. удаление через 30 секунд
call("requestDelete", id=t["id"])
time.sleep(33)
check("задача удалена через 30 с", task(call("state")["snapshot"], "Курсовая") is None)

print()
print("FAILED: " + ", ".join(failures) if failures else "ALL PASSED")
sys.exit(1 if failures else 0)
