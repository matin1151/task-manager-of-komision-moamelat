import json
import os
import sqlite3
import subprocess
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

ROOT = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(ROOT, "komision.db")
PORT = 8765

def init_db():
    with sqlite3.connect(DB_PATH) as db:
        db.execute("CREATE TABLE IF NOT EXISTS app_state (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL)")
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
    payload = json.dumps(value, ensure_ascii=False)
    with sqlite3.connect(DB_PATH) as db:
        db.execute("INSERT INTO app_state(id,payload) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", (payload,))

def notify_windows(message):
    if os.name != "nt":
        return
    script = "Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show(%s, 'دستیار کمیسیون معاملات')" % json.dumps(message)
    try:
        subprocess.Popen(["powershell", "-NoProfile", "-NonInteractive", "-Command", script], creationflags=subprocess.CREATE_NO_WINDOW)
    except Exception:
        pass

def alarm_loop():
    # The web UI remains usable without this loop; this provides alarms while it is closed.
    seen = set()
    while True:
        try:
            now = time.time()
            state = read_state()
            for tx in state.get("transactions", []):
                if tx.get("archived"):
                    continue
                for stage in tx.get("stages", []):
                    for item in stage.get("items", []):
                        due = item.get("dueAt")
                        if item.get("done") or not due:
                            continue
                        try:
                            due_ts = __import__('datetime').datetime.fromisoformat(due.replace('Z', '+00:00')).timestamp()
                        except Exception:
                            continue
                        key = "%s|%s" % (tx.get("id"), item.get("name"))
                        if due_ts <= now < due_ts + 86400 and key not in seen:
                            notify_windows("موعد کار: %s — %s" % (item.get("name", "کار"), tx.get("subject", "معامله")))
                            seen.add(key)
        except Exception:
            pass
        time.sleep(30)

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)
    def do_GET(self):
        if urlparse(self.path).path == "/api/state":
            body = json.dumps(read_state(), ensure_ascii=False).encode("utf-8")
            self.send_response(200); self.send_header("Content-Type", "application/json; charset=utf-8"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body); return
        super().do_GET()
    def do_POST(self):
        if urlparse(self.path).path != "/api/state":
            self.send_error(404); return
        try:
            length = int(self.headers.get("Content-Length", "0")); value = json.loads(self.rfile.read(length)); write_state(value)
            self.send_response(204); self.end_headers()
        except Exception as exc:
            self.send_error(400, str(exc))
    def log_message(self, *_):
        pass

if __name__ == "__main__":
    os.chdir(ROOT); init_db(); threading.Thread(target=alarm_loop, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
