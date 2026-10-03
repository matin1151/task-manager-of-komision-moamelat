import json
import os
import sqlite3
import subprocess
import threading
import time
from datetime import datetime, timedelta
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

ROOT = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(ROOT, "komision.db")
PORT = 8765
TEHRAN = ZoneInfo("Asia/Tehran")

def init_db():
    with sqlite3.connect(DB_PATH) as db:
        db.execute("CREATE TABLE IF NOT EXISTS app_state (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL)")
        db.execute("CREATE TABLE IF NOT EXISTS fired_alarms (alarm_key TEXT PRIMARY KEY, fired_at REAL NOT NULL)")
        if db.execute("SELECT 1 FROM app_state WHERE id=1").fetchone() is None:
            db.execute("INSERT INTO app_state(id,payload) VALUES(1,?)", (json.dumps({"transactions": [], "tasks": []}),))

def read_state():
    with sqlite3.connect(DB_PATH) as db:
        row = db.execute("SELECT payload FROM app_state WHERE id=1").fetchone()
    try:
        value = json.loads(row[0]) if row else {}
        return value if isinstance(value, dict) else {"transactions": [], "tasks": []}
    except Exception:
        return {"transactions": [], "tasks": []}

def write_state(value):
    if not isinstance(value, dict):
        raise ValueError("State must be a JSON object")
    value.setdefault("transactions", [])
    value.setdefault("tasks", [])
    payload = json.dumps(value, ensure_ascii=False)
    with sqlite3.connect(DB_PATH) as db:
        db.execute("INSERT INTO app_state(id,payload) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", (payload,))

def was_fired(key):
    with sqlite3.connect(DB_PATH) as db:
        return db.execute("SELECT 1 FROM fired_alarms WHERE alarm_key=?", (key,)).fetchone() is not None

def mark_fired(key, fired_at):
    with sqlite3.connect(DB_PATH) as db:
        db.execute("INSERT OR IGNORE INTO fired_alarms(alarm_key,fired_at) VALUES(?,?)", (key, fired_at))
        db.execute("DELETE FROM fired_alarms WHERE fired_at < ?", (time.time() - 180 * 86400,))

def notify_windows(message):
    if os.name != "nt":
        return
    script = "Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show(%s, 'دستیار کمیسیون معاملات')" % json.dumps(message)
    try:
        subprocess.Popen(["powershell", "-NoProfile", "-NonInteractive", "-Command", script], creationflags=subprocess.CREATE_NO_WINDOW)
    except Exception:
        pass

def jalali_to_gregorian(jy, jm, jd):
    breaks = [-61,9,38,199,426,686,756,818,1111,1181,1210,1635,2060,2097,2192,2262,2324,2394,2456,3178]
    gy, leap_j, jp, jump = jy + 621, -14, breaks[0], 0
    for jm_break in breaks[1:]:
        jump = jm_break - jp
        if jy < jm_break:
            break
        leap_j += (jump // 33) * 8 + ((jump % 33) // 4)
        jp = jm_break
    n = jy - jp
    leap_j += (n // 33) * 8 + (((n % 33) + 3) // 4)
    if jump % 33 == 4 and jump - n == 4:
        leap_j += 1
    leap_g = gy // 4 - ((gy // 100 + 1) * 3 // 4) - 150
    march = 20 + leap_j - leap_g
    days = (jm - 1) * 31 + (jd - 1) if jm <= 7 else (jm - 1) * 30 + 6 + (jd - 1)
    return datetime(gy, 3, march, tzinfo=TEHRAN) + timedelta(days=days)

def jalali_datetime_ts(date_text, time_text="00:00"):
    try:
        s = str(date_text).translate(str.maketrans("۰۱۲۳۴۵۶۷۸۹", "0123456789")).replace("-", "/").replace(".", "/")
        jy, jm, jd = [int(x) for x in s.split("/")]
        hh, mm = [int(x) for x in str(time_text or "00:00").split(":")[:2]]
        g = jalali_to_gregorian(jy, jm, jd)
        return g.replace(hour=hh, minute=mm, second=0, microsecond=0).timestamp()
    except Exception:
        return None

def iso_ts(value):
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=TEHRAN)
        return dt.timestamp()
    except Exception:
        return None

def alarm_events(state):
    events = []
    def add(tx, suffix, at, label):
        if at is not None:
            events.append((f"{tx.get('id')}|{suffix}", at, label, tx.get("subject", "معامله")))
    for tx in state.get("transactions", []):
        if tx.get("archived"):
            continue
        publication = iso_ts(tx.get("date")) if tx.get("date") else None
        if publication is not None:
            add(tx, "publication|day", publication, "روز انتشار / شروع معامله")
            add(tx, "publication|minus1", publication - 86400, "۱ روز مانده به انتشار / شروع معامله")
        for row in tx.get("suggestedDates", []):
            base = jalali_datetime_ts(row.get("date"), row.get("time", "00:00"))
            key = row.get("key")
            if base is None:
                continue
            if key == "بازگشایی":
                add(tx, "opening|3d", base - 3*86400, "۳ روز مانده به بازگشایی — دعوت اعضای کمیسیون و سازمان بازرسی")
                add(tx, "opening|24h", base - 86400, "۲۴ ساعت مانده به بازگشایی")
                add(tx, "opening|2h", base - 7200, "۲ ساعت مانده به بازگشایی")
                add(tx, "opening|now", base, "زمان بازگشایی")
                add(tx, "deposit|1d", base - 86400, "۱ روز مانده به بازگشایی — کنترل اصل سپرده")
                add(tx, "deposit|now", base, "روز بازگشایی — کنترل اصل سپرده")
            elif key == "پیشنهاد":
                add(tx, "offer|2h", base - 7200, "۲ ساعت مانده به پایان ارسال پیشنهاد")
                add(tx, "offer|now", base, "پایان ارسال پیشنهاد")
            elif key == "اسناد":
                add(tx, "docs|1d", base - 86400, "۱ روز مانده به پایان دریافت اسناد")
                add(tx, "docs|now", base, "پایان دریافت اسناد")
            elif key == "برنده":
                add(tx, "winner|now", base, "زمان اعلام برنده")
        for si, stage in enumerate(tx.get("stages", [])):
            for ii, item in enumerate(stage.get("items", [])):
                if item.get("done") or not item.get("dueAt"):
                    continue
                due = iso_ts(item.get("dueAt"))
                if due is not None:
                    identity = f"{si}|{ii}"
                    add(tx, f"task|{identity}|24h", due - 86400, "۱ روز مانده — " + item.get("name", "کار"))
                    add(tx, f"task|{identity}|now", due, "موعد کار — " + item.get("name", "کار"))
    return events

def alarm_loop():
    while True:
        try:
            now = time.time()
            for key, at, label, subject in alarm_events(read_state()):
                if at <= now < at + 36 * 3600 and not was_fired(key):
                    notify_windows(f"{label} — {subject}")
                    mark_fired(key, now)
        except Exception:
            pass
        time.sleep(30)

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)
    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/health":
            body = b'{"ok":true}'
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body); return
        if path == "/api/state":
            body = json.dumps(read_state(), ensure_ascii=False).encode("utf-8")
            self.send_response(200); self.send_header("Content-Type", "application/json; charset=utf-8"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body); return
        super().do_GET()
    def do_POST(self):
        if urlparse(self.path).path != "/api/state":
            self.send_error(404); return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 10_000_000:
                raise ValueError("Invalid request size")
            value = json.loads(self.rfile.read(length))
            write_state(value)
            self.send_response(204); self.end_headers()
        except Exception as exc:
            self.send_error(400, str(exc))
    def log_message(self, *_):
        pass

if __name__ == "__main__":
    os.chdir(ROOT)
    init_db()
    threading.Thread(target=alarm_loop, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
