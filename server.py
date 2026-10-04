import json
import os
import secrets
import shutil
import sqlite3
import sys
import threading
import time
from datetime import datetime, timedelta
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

ROOT = os.path.dirname(os.path.abspath(__file__))
APP_NAME = "DastyarKomision"
DATA_DIR = os.environ.get("DASTYAR_KOMISION_DATA_DIR") or os.path.join(
    os.environ.get("LOCALAPPDATA", ROOT),
    "DastyarKomisionData",
)
DB_PATH = os.path.join(DATA_DIR, "komision.db")
PID_PATH = os.path.join(DATA_DIR, "server.pid")
TOKEN_PATH = os.path.join(DATA_DIR, "api.token")
PORT_PATH = os.path.join(DATA_DIR, "server.port")
BACKUP_DIR = os.path.join(DATA_DIR, "backups")
PORT = int(os.environ.get("DASTYAR_KOMISION_PORT", "8765"))
TEHRAN_OFFSET = timedelta(hours=3, minutes=30)
ALLOWED_HOSTS = {f"127.0.0.1:{PORT}", f"localhost:{PORT}"}


class StateConflict(Exception):
    def __init__(self, state, version):
        super().__init__("State changed in another tab")
        self.state = state
        self.version = version


def connect_db():
    db = sqlite3.connect(DB_PATH, timeout=10)
    db.execute("PRAGMA busy_timeout=10000")
    db.execute("PRAGMA journal_mode=WAL")
    return db

def init_db():
    os.makedirs(DATA_DIR, exist_ok=True)
    os.makedirs(BACKUP_DIR, exist_ok=True)
    if not os.path.exists(TOKEN_PATH):
        with open(TOKEN_PATH, "w", encoding="ascii") as token_file:
            token_file.write(secrets.token_urlsafe(32))
    with connect_db() as db:
        db.execute("CREATE TABLE IF NOT EXISTS app_state (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL)")
        db.execute("CREATE TABLE IF NOT EXISTS state_meta (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL)")
        db.execute("CREATE TABLE IF NOT EXISTS fired_alarms (alarm_key TEXT PRIMARY KEY, fired_at REAL NOT NULL)")
        if db.execute("SELECT 1 FROM app_state WHERE id=1").fetchone() is None:
            db.execute("INSERT INTO app_state(id,payload) VALUES(1,?)", (json.dumps({"transactions": [], "tasks": []}),))
        if db.execute("SELECT 1 FROM state_meta WHERE id=1").fetchone() is None:
            db.execute("INSERT INTO state_meta(id,version) VALUES(1,1)")


def api_token():
    try:
        with open(TOKEN_PATH, "r", encoding="ascii") as token_file:
            return token_file.read().strip()
    except OSError:
        return ""

def read_state_bundle(db=None):
    owns_db = db is None
    db = db or connect_db()
    row = db.execute("SELECT payload FROM app_state WHERE id=1").fetchone()
    version_row = db.execute("SELECT version FROM state_meta WHERE id=1").fetchone()
    if owns_db:
        db.close()
    try:
        value = json.loads(row[0]) if row else {}
        state = value if isinstance(value, dict) else {"transactions": [], "tasks": []}
    except Exception:
        state = {"transactions": [], "tasks": []}
    return state, int(version_row[0] if version_row else 1)


def read_state():
    return read_state_bundle()[0]


def backup_database():
    if not os.path.exists(DB_PATH):
        return
    os.makedirs(BACKUP_DIR, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    target = os.path.join(BACKUP_DIR, f"komision-{stamp}.db")
    shutil.copy2(DB_PATH, target)
    backups = sorted(
        (os.path.join(BACKUP_DIR, name) for name in os.listdir(BACKUP_DIR) if name.endswith(".db")),
        key=os.path.getmtime,
        reverse=True,
    )
    for old in backups[30:]:
        try:
            os.remove(old)
        except OSError:
            pass

def write_state(value, expected_version=None):
    if not isinstance(value, dict):
        raise ValueError("State must be a JSON object")
    value.setdefault("transactions", [])
    value.setdefault("tasks", [])
    payload = json.dumps(value, ensure_ascii=False)
    with connect_db() as db:
        db.execute("BEGIN IMMEDIATE")
        current_state, current_version = read_state_bundle(db)
        if expected_version is not None and int(expected_version) != current_version:
            raise StateConflict(current_state, current_version)
        backup_database()
        db.execute("UPDATE app_state SET payload=? WHERE id=1", (payload,))
        new_version = current_version + 1
        db.execute("UPDATE state_meta SET version=? WHERE id=1", (new_version,))
        db.commit()
    return new_version

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
    return datetime(gy, 3, march) + timedelta(days=days)

def jalali_datetime_ts(date_text, time_text="00:00"):
    try:
        s = str(date_text).translate(str.maketrans("۰۱۲۳۴۵۶۷۸۹", "0123456789")).replace("-", "/").replace(".", "/")
        jy, jm, jd = [int(x) for x in s.split("/")]
        hh, mm = [int(x) for x in str(time_text or "00:00").split(":")[:2]]
        g = jalali_to_gregorian(jy, jm, jd)
        local_dt = g.replace(hour=hh, minute=mm, second=0, microsecond=0)
        return (local_dt - TEHRAN_OFFSET).replace(tzinfo=__import__("datetime").timezone.utc).timestamp()
    except Exception:
        return None

def iso_ts(value):
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=__import__("datetime").timezone(TEHRAN_OFFSET))
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

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def request_is_allowed(self, require_token=False):
        if self.headers.get("Host", "") not in ALLOWED_HOSTS:
            return False
        origin = self.headers.get("Origin")
        if origin and origin not in {f"http://127.0.0.1:{PORT}", f"http://localhost:{PORT}"}:
            return False
        return not require_token or secrets.compare_digest(self.headers.get("X-Dastyar-Token", ""), api_token())

    def send_json(self, status, value, extra_headers=None):
        body = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        for key, item in (extra_headers or {}).items():
            self.send_header(key, str(item))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if not self.request_is_allowed():
            self.send_error(403)
            return
        if path == "/api/session":
            self.send_json(200, {"token": api_token(), "port": PORT})
            return
        if path == "/api/health":
            body = json.dumps({
                "ok": True,
                "app": APP_NAME,
                "port": PORT,
                "dataDir": DATA_DIR,
                "database": DB_PATH,
            }, ensure_ascii=False).encode("utf-8")
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body); return
        if path == "/api/state":
            state, version = read_state_bundle()
            self.send_json(200, state, {"X-State-Version": version, "ETag": f'"{version}"'})
            return
        super().do_GET()
    def do_POST(self):
        if urlparse(self.path).path != "/api/state":
            self.send_error(404); return
        if not self.request_is_allowed(require_token=True):
            self.send_error(403)
            return
        try:
            content_type = self.headers.get("Content-Type", "").split(";", 1)[0].strip().lower()
            if content_type != "application/json":
                raise ValueError("Content-Type must be application/json")
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 10_000_000:
                raise ValueError("Invalid request size")
            incoming = json.loads(self.rfile.read(length))
            expected_version = self.headers.get("If-Match") or incoming.get("version") if isinstance(incoming, dict) else None
            if isinstance(expected_version, str):
                expected_version = expected_version.strip('"')
            value = incoming.get("state") if isinstance(incoming, dict) and "state" in incoming else incoming
            new_version = write_state(value, expected_version)
            self.send_json(200, {"ok": True, "version": new_version})
        except StateConflict as exc:
            self.send_json(409, {"ok": False, "error": "conflict", "state": exc.state, "version": exc.version})
        except Exception as exc:
            self.send_error(400, str(exc))
    def log_message(self, *_):
        pass

if __name__ == "__main__":
    os.chdir(ROOT)
    init_db()
    try:
        with open(PID_PATH, "w", encoding="utf-8") as pid_file:
            pid_file.write(str(os.getpid()))
        with open(PORT_PATH, "w", encoding="ascii") as port_file:
            port_file.write(str(PORT))
    except Exception:
        pass
    try:
        ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)
