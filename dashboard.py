#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import socket
import sqlite3
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

# Main game and database settings.
GAME_TITLE = "DarkTsunami Keep"
DEFAULT_DB = Path.home() / ".nomadnetwork" / "storage" / "pages" / ".darktsunami_keep" / "game.sqlite3"
ONLINE_WINDOW = 900
REFRESH_MS = 2000
BURN_SHIFT_MS = 3000
BURN_IDLE_ROTATE_AFTER = 300
BURN_TAB_ROTATE_MS = 120000
BURN_MARGIN = 24
BURN_OFFSETS = ((0, 0), (3, 1), (6, 3), (9, 5), (12, 7), (14, 8), (12, 4), (10, 0), (7, -3), (3, -6), (0, -8), (-3, -6), (-7, -3), (-10, 0), (-12, 4), (-14, 8), (-12, 7), (-9, 5), (-6, 3), (-3, 1))


# Convert a timestamp into a readable date and time.
def fmt_time(ts: int | float | None) -> str:
    if not ts:
        return "-"
    try:
        return datetime.fromtimestamp(float(ts)).strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        return "-"


# Show how long ago a timestamp occurred.
def fmt_age(ts: int | float | None) -> str:
    if not ts:
        return "-"
    sec = max(0, int(time.time() - float(ts)))
    if sec < 60:
        return f"{sec}s"
    if sec < 3600:
        return f"{sec // 60}m"
    if sec < 86400:
        return f"{sec // 3600}h {sec % 3600 // 60}m"
    return f"{sec // 86400}d {sec % 86400 // 3600}h"


# Convert byte counts into easier-to-read sizes.
def fmt_bytes(n: int | float) -> str:
    n = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


# Load a player state JSON record from SQLite.
def state(row: sqlite3.Row) -> dict[str, Any]:
    try:
        return json.loads(row["state_json"])
    except Exception:
        return {}


# Open the live game database in read-only mode.
def ro_connect(db_path: Path) -> sqlite3.Connection:
    db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=3.0)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA busy_timeout=3000")
    return db


# Check whether a database table exists.
def table_exists(db: sqlite3.Connection, name: str) -> bool:
    return db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)).fetchone() is not None


# Return one value from a database query.
def scalar(db: sqlite3.Connection, sql: str, args: tuple = ()) -> Any:
    row = db.execute(sql, args).fetchone()
    return row[0] if row else 0


# Read the current multiplayer game state for the dashboard.
def database_snapshot(db_path: Path, integrity: bool = False) -> dict[str, Any]:
    result: dict[str, Any] = {
        "ok": False,
        "path": str(db_path),
        "players": [],
        "parties": [],
        "duels": [],
        "board": [],
        "activity": [],
        "raid_events": [],
        "meta": {},
        "counts": {},
    }
    if not db_path.exists():
        result["error"] = "Database not found"
        return result
    try:
        with ro_connect(db_path) as db:
            required = ["players", "scores", "board", "parties", "party_members", "raid_state", "duels"]
            missing = [name for name in required if not table_exists(db, name)]
            if missing:
                result["error"] = "Missing tables: " + ", ".join(missing)
                return result
            now = int(time.time())
            player_rows = db.execute("SELECT player_key,state_json,updated_at,identity_hash FROM players ORDER BY updated_at DESC").fetchall()
            players = []
            for row in player_rows:
                s = state(row)
                players.append({
                    "address": row["player_key"],
                    "identity_hash": row["identity_hash"] or "",
                    "name": s.get("name", "Unknown"),
                    "class": s.get("class", ""),
                    "level": int(s.get("level", 0)),
                    "hp": int(s.get("hp", 0)),
                    "max_hp": int(s.get("max_hp", 0)),
                    "xp": int(s.get("xp", 0)),
                    "gold": int(s.get("gold", 0)),
                    "potions": int(s.get("potions", 0)),
                    "rooms": int(s.get("rooms", 0)),
                    "deepest": int(s.get("deepest", 0)),
                    "victories": int(s.get("victories", 0)),
                    "deaths": int(s.get("deaths", 0)),
                    "duel_wins": int(s.get("duel_wins", 0)),
                    "score": int(s.get("score", 0)),
                    "room_type": s.get("room_type", ""),
                    "enemy": (s.get("enemy") or {}).get("name", "") if isinstance(s.get("enemy"), dict) else "",
                    "weapon": (s.get("weapon") or {}).get("name", "") if isinstance(s.get("weapon"), dict) else "",
                    "armor": (s.get("armor") or {}).get("name", "") if isinstance(s.get("armor"), dict) else "",
                    "created": int(s.get("created", 0)),
                    "updated_at": int(row["updated_at"]),
                    "online": int(row["updated_at"]) >= now - ONLINE_WINDOW,
                    "state": s,
                })
            result["players"] = players
            score_names = {r["player_key"]: r["name"] for r in db.execute("SELECT player_key,name FROM scores").fetchall()}
            party_rows = db.execute("SELECT party_id,leader,name,created_at FROM parties ORDER BY created_at DESC").fetchall()
            parties = []
            for row in party_rows:
                members = db.execute("SELECT player_key,joined_at FROM party_members WHERE party_id=? ORDER BY joined_at", (row["party_id"],)).fetchall()
                raid_row = db.execute("SELECT state_json,updated_at FROM raid_state WHERE party_id=?", (row["party_id"],)).fetchone()
                raid = {}
                raid_updated = 0
                if raid_row:
                    try:
                        raid = json.loads(raid_row["state_json"])
                    except Exception:
                        raid = {}
                    raid_updated = int(raid_row["updated_at"])
                actions = []
                if table_exists(db, "raid_actions"):
                    actions = [dict(r) for r in db.execute("SELECT player_key,skill_used,damage,healing FROM raid_actions WHERE party_id=? ORDER BY damage DESC", (row["party_id"],)).fetchall()]
                parties.append({
                    "party_id": row["party_id"],
                    "name": row["name"],
                    "leader": row["leader"],
                    "leader_name": score_names.get(row["leader"], row["leader"][:8]),
                    "created_at": int(row["created_at"]),
                    "members": [{"address": m["player_key"], "name": score_names.get(m["player_key"], m["player_key"][:8]), "joined_at": int(m["joined_at"])} for m in members],
                    "raid": raid,
                    "raid_updated": raid_updated,
                    "actions": actions,
                })
            result["parties"] = parties
            result["duels"] = [dict(r) for r in db.execute("SELECT id,challenger,target,status,turn,hp_challenger,hp_target,log,created_at,updated_at FROM duels ORDER BY updated_at DESC LIMIT 500").fetchall()]
            result["board"] = [dict(r) for r in db.execute("SELECT id,player_key,name,message,created_at FROM board ORDER BY id DESC LIMIT 500").fetchall()]
            if table_exists(db, "activity"):
                result["activity"] = [dict(r) for r in db.execute("SELECT id,player_key,action,detail,created_at FROM activity ORDER BY id DESC LIMIT 1000").fetchall()]
            if table_exists(db, "raid_events"):
                result["raid_events"] = [dict(r) for r in db.execute("SELECT id,party_id,player_key,text,created_at FROM raid_events ORDER BY id DESC LIMIT 500").fetchall()]
            if table_exists(db, "meta"):
                result["meta"] = {r["key"]: r["value"] for r in db.execute("SELECT key,value FROM meta").fetchall()}
            active_raids = sum(1 for p in parties if p["raid"].get("status") == "active")
            counts = {
                "players": len(players),
                "online": sum(1 for p in players if p["online"]),
                "parties": len(parties),
                "active_raids": active_raids,
                "pending_duels": sum(1 for d in result["duels"] if d["status"] == "pending"),
                "active_duels": sum(1 for d in result["duels"] if d["status"] == "active"),
                "complete_duels": sum(1 for d in result["duels"] if d["status"] == "complete"),
                "board_posts": int(scalar(db, "SELECT COUNT(*) FROM board")),
                "activity_events": int(scalar(db, "SELECT COUNT(*) FROM activity")) if table_exists(db, "activity") else 0,
                "raid_events": int(scalar(db, "SELECT COUNT(*) FROM raid_events")) if table_exists(db, "raid_events") else 0,
                "total_score": sum(p["score"] for p in players),
                "total_gold": sum(p["gold"] for p in players),
                "total_bosses": sum(p["victories"] for p in players),
                "total_deaths": sum(p["deaths"] for p in players),
                "total_duel_wins": sum(p["duel_wins"] for p in players),
                "max_level": max((p["level"] for p in players), default=0),
                "deepest": max((p["deepest"] for p in players), default=0),
            }
            result["counts"] = counts
            result["ok"] = True
            result["quick_check"] = scalar(db, "PRAGMA quick_check") if integrity else None
            return result
    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
        return result


# Read total and available memory from Linux.
def linux_mem() -> tuple[int, int]:
    try:
        values = {}
        for line in Path("/proc/meminfo").read_text().splitlines():
            if ":" in line:
                key, value = line.split(":", 1)
                values[key] = int(value.strip().split()[0]) * 1024
        return int(values.get("MemTotal", 0)), int(values.get("MemAvailable", 0))
    except Exception:
        return 0, 0


# Collect CPU, memory, disk, uptime, and database sizes.
def host_snapshot(db_path: Path, cpu_prev: tuple[int, int] | None = None) -> tuple[dict[str, Any], tuple[int, int] | None]:
    cpu_now = None
    cpu_pct = None
    try:
        parts = [int(x) for x in Path("/proc/stat").read_text().splitlines()[0].split()[1:]]
        idle = parts[3] + (parts[4] if len(parts) > 4 else 0)
        total = sum(parts)
        cpu_now = (idle, total)
        if cpu_prev and total > cpu_prev[1]:
            idle_delta = idle - cpu_prev[0]
            total_delta = total - cpu_prev[1]
            cpu_pct = max(0.0, min(100.0, 100.0 * (1.0 - idle_delta / total_delta)))
    except Exception:
        pass
    mem_total, mem_avail = linux_mem()
    try:
        disk = shutil.disk_usage(db_path.parent if db_path.parent.exists() else Path.home())
    except Exception:
        disk = shutil.disk_usage(Path.home())
    try:
        uptime = float(Path("/proc/uptime").read_text().split()[0])
    except Exception:
        uptime = 0.0
    try:
        load = os.getloadavg()
    except Exception:
        load = (0.0, 0.0, 0.0)
    files = {}
    for suffix in ("", "-wal", "-shm"):
        path = Path(str(db_path) + suffix)
        files[suffix or "db"] = path.stat().st_size if path.exists() else 0
    return ({
        "hostname": socket.gethostname(),
        "os": f"{platform.system()} {platform.release()}",
        "arch": platform.machine(),
        "python": platform.python_version(),
        "cpu_pct": cpu_pct,
        "load1": load[0],
        "load5": load[1],
        "load15": load[2],
        "mem_total": mem_total,
        "mem_used": max(0, mem_total - mem_avail),
        "disk_total": disk.total,
        "disk_used": disk.used,
        "disk_free": disk.free,
        "uptime": uptime,
        "db_size": files["db"],
        "wal_size": files["-wal"],
        "shm_size": files["-shm"],
    }, cpu_now)


# Print dashboard data as JSON when --check is used.
def check_mode(db_path: Path) -> int:
    snap = database_snapshot(db_path, integrity=True)
    host, _ = host_snapshot(db_path)
    out = {"game": GAME_TITLE, "database": snap, "host": host}
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if snap.get("ok") else 1


# Start the local Tkinter administration dashboard.
def run_gui(db_path: Path) -> int:
    import tkinter as tk
    from tkinter import messagebox, ttk

    # Build and update the live server dashboard.
    class Dashboard:
        # Set up the window, tabs, timers, and input tracking.
        def __init__(self, root: tk.Tk):
            self.root = root
            self.db_path = db_path
            self.cpu_prev = None
            self.snapshot: dict[str, Any] = {}
            self.last_integrity = 0.0
            self.last_quick_check = "not checked"
            self.player_by_item: dict[str, dict[str, Any]] = {}
            self.party_by_item: dict[str, dict[str, Any]] = {}
            self.last_input = time.monotonic()
            self.last_tab_rotation = time.monotonic()
            self.shift_index = 0
            self.root.title("DarkTsunami Keep — Server Dashboard")
            self.root.geometry("1500x900")
            self.root.minsize(1150, 700)
            self.style = ttk.Style()
            try:
                self.style.theme_use("clam")
            except Exception:
                pass
            self.style.configure("Treeview", rowheight=26)
            self.style.configure("Title.TLabel", font=("TkDefaultFont", 18, "bold"))
            self.style.configure("KPI.TLabel", font=("TkDefaultFont", 16, "bold"))
            self.style.configure("Small.TLabel", font=("TkDefaultFont", 9))
            self.shell = ttk.Frame(root)
            self.shell.place(x=BURN_MARGIN, y=BURN_MARGIN, relwidth=1, relheight=1, width=-(BURN_MARGIN * 2), height=-(BURN_MARGIN * 2))
            top = ttk.Frame(self.shell, padding=(12, 10))
            top.pack(fill="x")
            ttk.Label(top, text="DarkTsunami Keep", style="Title.TLabel").pack(side="left")
            self.status = ttk.Label(top, text="Starting…")
            self.status.pack(side="right")
            self.notebook = ttk.Notebook(self.shell)
            self.notebook.pack(fill="both", expand=True, padx=10, pady=(0, 10))
            self.build_overview()
            self.build_players()
            self.build_parties()
            self.build_duels()
            self.build_tavern()
            self.build_activity()
            self.build_database()
            self.root.bind_all("<Motion>", self.mark_input, add="+")
            self.root.bind_all("<Button>", self.mark_input, add="+")
            self.root.bind_all("<KeyPress>", self.mark_input, add="+")
            self.root.bind_all("<MouseWheel>", self.mark_input, add="+")
            self.root.after(BURN_SHIFT_MS, self.burn_shift)
            self.root.after(5000, self.burn_cycle)
            self.refresh()

        # Record activity so automatic tab rotation pauses.
        def mark_input(self, event=None):
            self.last_input = time.monotonic()
            self.last_tab_rotation = self.last_input

        # Move the dashboard slightly to reduce screen burn-in.
        def burn_shift(self):
            self.shift_index = (self.shift_index + 1) % len(BURN_OFFSETS)
            x, y = BURN_OFFSETS[self.shift_index]
            self.shell.place_configure(x=BURN_MARGIN + x, y=BURN_MARGIN + y)
            self.root.after(BURN_SHIFT_MS, self.burn_shift)

        # Rotate tabs after the dashboard has been idle.
        def burn_cycle(self):
            now = time.monotonic()
            if now - self.last_input >= BURN_IDLE_ROTATE_AFTER and now - self.last_tab_rotation >= BURN_TAB_ROTATE_MS:
                tabs = self.notebook.tabs()
                if tabs:
                    current = self.notebook.index(self.notebook.select())
                    self.notebook.select(tabs[(current + 1) % len(tabs)])
                    self.last_tab_rotation = now
            self.root.after(5000, self.burn_cycle)

        # Create one dashboard tab.
        def frame(self, title: str) -> ttk.Frame:
            f = ttk.Frame(self.notebook, padding=10)
            self.notebook.add(f, text=title)
            return f

        # Build the overview cards and server summary.
        def build_overview(self):
            f = self.frame("Overview")
            self.kpis = {}
            labels = [
                ("players", "Players"), ("online", "Active 15m"), ("parties", "Parties"), ("active_raids", "Active Raids"),
                ("active_duels", "Active Duels"), ("pending_duels", "Pending Duels"), ("max_level", "Max Level"), ("deepest", "Deepest"),
                ("total_score", "Total Score"), ("total_gold", "Total Gold"), ("total_bosses", "Boss Kills"), ("total_deaths", "Deaths"),
            ]
            cards = ttk.Frame(f)
            cards.pack(fill="x")
            for i, (key, title) in enumerate(labels):
                box = ttk.LabelFrame(cards, text=title, padding=9)
                box.grid(row=i // 4, column=i % 4, padx=5, pady=5, sticky="nsew")
                val = ttk.Label(box, text="0", style="KPI.TLabel")
                val.pack()
                self.kpis[key] = val
            for col in range(4):
                cards.columnconfigure(col, weight=1)
            bottom = ttk.Frame(f)
            bottom.pack(fill="both", expand=True, pady=(10, 0))
            self.server_text = tk.Text(bottom, height=16, wrap="none")
            self.server_text.pack(side="left", fill="both", expand=True)
            self.leaders = ttk.Treeview(bottom, columns=("name", "level", "depth", "score", "age"), show="headings", height=14)
            for c, title, width in (("name", "Player", 160), ("level", "Level", 70), ("depth", "Depth", 70), ("score", "Score", 100), ("age", "Last Seen", 100)):
                self.leaders.heading(c, text=title)
                self.leaders.column(c, width=width, anchor="center" if c != "name" else "w")
            self.leaders.pack(side="left", fill="both", expand=True, padx=(10, 0))

        # Build a table with a details panel below it.
        def tree_tab(self, title: str, cols: list[tuple[str, str, int]]):
            f = self.frame(title)
            pane = ttk.Panedwindow(f, orient="vertical")
            pane.pack(fill="both", expand=True)
            top = ttk.Frame(pane)
            bottom = ttk.Frame(pane)
            pane.add(top, weight=3)
            pane.add(bottom, weight=2)
            tree = ttk.Treeview(top, columns=[c[0] for c in cols], show="headings")
            y = ttk.Scrollbar(top, orient="vertical", command=tree.yview)
            x = ttk.Scrollbar(top, orient="horizontal", command=tree.xview)
            tree.configure(yscrollcommand=y.set, xscrollcommand=x.set)
            tree.grid(row=0, column=0, sticky="nsew")
            y.grid(row=0, column=1, sticky="ns")
            x.grid(row=1, column=0, sticky="ew")
            top.rowconfigure(0, weight=1)
            top.columnconfigure(0, weight=1)
            for key, text, width in cols:
                tree.heading(key, text=text)
                tree.column(key, width=width, minwidth=60, anchor="w")
            details = tk.Text(bottom, wrap="none", height=12)
            dy = ttk.Scrollbar(bottom, orient="vertical", command=details.yview)
            dx = ttk.Scrollbar(bottom, orient="horizontal", command=details.xview)
            details.configure(yscrollcommand=dy.set, xscrollcommand=dx.set)
            details.grid(row=0, column=0, sticky="nsew")
            dy.grid(row=0, column=1, sticky="ns")
            dx.grid(row=1, column=0, sticky="ew")
            bottom.rowconfigure(0, weight=1)
            bottom.columnconfigure(0, weight=1)
            return tree, details

        # Build the player and LXMF statistics tab.
        def build_players(self):
            cols = [("name", "Name", 140), ("address", "LXMF Address", 275), ("class", "Class", 90), ("level", "Lvl", 55), ("hp", "HP", 90), ("xp", "XP", 70), ("gold", "Gold", 65), ("rooms", "Rooms", 70), ("deepest", "Depth", 70), ("bosses", "Bosses", 70), ("deaths", "Deaths", 70), ("duels", "Duel Wins", 80), ("score", "Score", 85), ("seen", "Last Seen", 100)]
            self.players_tree, self.player_details = self.tree_tab("Players", cols)
            self.players_tree.bind("<<TreeviewSelect>>", self.show_player)

        # Build the multiplayer party and raid tab.
        def build_parties(self):
            cols = [("name", "Party", 180), ("id", "ID", 90), ("leader", "Leader", 150), ("members", "Members", 80), ("raid", "Raid", 210), ("hp", "Raid HP", 120), ("status", "Status", 90), ("age", "Updated", 100)]
            self.parties_tree, self.party_details = self.tree_tab("Parties & Raids", cols)
            self.parties_tree.bind("<<TreeviewSelect>>", self.show_party)

        # Build the player duel tab.
        def build_duels(self):
            cols = [("id", "ID", 60), ("challenger", "Challenger", 200), ("target", "Target", 200), ("status", "Status", 90), ("turn", "Turn", 200), ("hp1", "Challenger HP", 110), ("hp2", "Target HP", 100), ("age", "Updated", 100), ("log", "Last Action", 360)]
            self.duels_tree, self.duel_details = self.tree_tab("Duels", cols)
            self.duels_tree.bind("<<TreeviewSelect>>", self.show_duel)

        # Build the shared tavern message tab.
        def build_tavern(self):
            cols = [("id", "ID", 60), ("name", "Player", 150), ("address", "LXMF Address", 275), ("time", "Time", 150), ("message", "Message", 600)]
            self.tavern_tree, self.tavern_details = self.tree_tab("Tavern", cols)
            self.tavern_tree.bind("<<TreeviewSelect>>", self.show_tavern)

        # Build the recent activity tab.
        def build_activity(self):
            cols = [("id", "ID", 70), ("time", "Time", 155), ("player", "Player", 150), ("address", "LXMF Address", 275), ("action", "Action", 160), ("detail", "Detail", 600)]
            self.activity_tree, self.activity_details = self.tree_tab("Activity", cols)
            self.activity_tree.bind("<<TreeviewSelect>>", self.show_activity)

        # Build the database health tab.
        def build_database(self):
            f = self.frame("Database")
            controls = ttk.Frame(f)
            controls.pack(fill="x", pady=(0, 8))
            ttk.Label(controls, text=str(self.db_path)).pack(side="left")
            ttk.Button(controls, text="Refresh now", command=self.refresh).pack(side="right")
            self.database_text = tk.Text(f, wrap="none")
            self.database_text.pack(fill="both", expand=True)

        # Clear old rows before refreshing a table.
        def clear_tree(self, tree):
            tree.delete(*tree.get_children())

        # Match LXMF addresses to player names.
        def names(self) -> dict[str, str]:
            return {p["address"]: p["name"] for p in self.snapshot.get("players", [])}

        # Replace text inside a read-only text panel.
        def put_text(self, widget, text: str):
            widget.configure(state="normal")
            widget.delete("1.0", "end")
            widget.insert("1.0", text)
            widget.configure(state="disabled")

        # Reload game and host statistics on the timer.
        def refresh(self):
            do_integrity = time.time() - self.last_integrity >= 60
            self.snapshot = database_snapshot(self.db_path, integrity=do_integrity)
            if do_integrity and self.snapshot.get("quick_check"):
                self.last_quick_check = self.snapshot["quick_check"]
                self.last_integrity = time.time()
            self.snapshot["quick_check"] = self.last_quick_check
            host, self.cpu_prev = host_snapshot(self.db_path, self.cpu_prev)
            self.snapshot["host"] = host
            if self.snapshot.get("ok"):
                self.status.configure(text=f"ONLINE • refreshed {datetime.now().strftime('%H:%M:%S')}")
            else:
                self.status.configure(text=f"DATABASE ERROR • {self.snapshot.get('error', 'unknown')}")
            self.refresh_overview()
            self.refresh_players()
            self.refresh_parties()
            self.refresh_duels()
            self.refresh_tavern()
            self.refresh_activity()
            self.refresh_database()
            self.root.after(REFRESH_MS, self.refresh)

        # Update overview cards, server stats, and leaderboard.
        def refresh_overview(self):
            c = self.snapshot.get("counts", {})
            for key, widget in self.kpis.items():
                widget.configure(text=f"{c.get(key, 0):,}")
            h = self.snapshot.get("host", {})
            cpu = "warming up" if h.get("cpu_pct") is None else f"{h['cpu_pct']:.1f}%"
            mem_pct = (100 * h.get("mem_used", 0) / h.get("mem_total", 1)) if h.get("mem_total") else 0
            disk_pct = (100 * h.get("disk_used", 0) / h.get("disk_total", 1)) if h.get("disk_total") else 0
            lines = [
                "SERVER",
                f"Host: {h.get('hostname', '-')}",
                f"OS: {h.get('os', '-')} • {h.get('arch', '-')}",
                f"Python: {h.get('python', '-')}",
                f"CPU: {cpu} • load {h.get('load1', 0):.2f} / {h.get('load5', 0):.2f} / {h.get('load15', 0):.2f}",
                f"Memory: {fmt_bytes(h.get('mem_used', 0))} / {fmt_bytes(h.get('mem_total', 0))} ({mem_pct:.1f}%)",
                f"Disk: {fmt_bytes(h.get('disk_used', 0))} / {fmt_bytes(h.get('disk_total', 0))} ({disk_pct:.1f}%)",
                f"Uptime: {fmt_age(time.time() - h.get('uptime', 0)) if h.get('uptime') else '-'}",
                "",
                "GAME DATABASE",
                f"Path: {self.db_path}",
                f"DB: {fmt_bytes(h.get('db_size', 0))} • WAL: {fmt_bytes(h.get('wal_size', 0))} • SHM: {fmt_bytes(h.get('shm_size', 0))}",
                f"Integrity: {self.snapshot.get('quick_check', '-')}",
                f"Version: {self.snapshot.get('meta', {}).get('game_version', '-')}",
                f"Schema: {self.snapshot.get('meta', {}).get('schema_version', '-')}",
                f"Activity events: {c.get('activity_events', 0):,} • Raid events: {c.get('raid_events', 0):,} • Tavern posts: {c.get('board_posts', 0):,}",
            ]
            self.put_text(self.server_text, "\n".join(lines))
            self.clear_tree(self.leaders)
            leaders = sorted(self.snapshot.get("players", []), key=lambda p: (p["score"], p["deepest"], p["level"]), reverse=True)[:20]
            for p in leaders:
                self.leaders.insert("", "end", values=(p["name"], p["level"], p["deepest"], p["score"], "ACTIVE" if p["online"] else fmt_age(p["updated_at"])))

        # Refresh all player statistics.
        def refresh_players(self):
            selected = self.players_tree.selection()
            selected_addr = None
            if selected:
                selected_addr = self.player_by_item.get(selected[0], {}).get("address")
            self.clear_tree(self.players_tree)
            self.player_by_item = {}
            new_sel = None
            for p in self.snapshot.get("players", []):
                iid = self.players_tree.insert("", "end", values=(p["name"], p["address"], p["class"], p["level"], f"{p['hp']}/{p['max_hp']}", p["xp"], p["gold"], p["rooms"], p["deepest"], p["victories"], p["deaths"], p["duel_wins"], p["score"], "ACTIVE" if p["online"] else fmt_age(p["updated_at"])))
                self.player_by_item[iid] = p
                if p["address"] == selected_addr:
                    new_sel = iid
            if new_sel:
                self.players_tree.selection_set(new_sel)
            elif self.player_by_item:
                first = next(iter(self.player_by_item))
                self.players_tree.selection_set(first)
                self.players_tree.focus(first)
            self.show_player()

        # Refresh parties and shared raid state.
        def refresh_parties(self):
            self.clear_tree(self.parties_tree)
            self.party_by_item = {}
            for p in self.snapshot.get("parties", []):
                raid = p["raid"]
                hp = f"{raid.get('hp', 0)}/{raid.get('max_hp', 0)}" if raid else "-"
                iid = self.parties_tree.insert("", "end", values=(p["name"], p["party_id"], p["leader_name"], len(p["members"]), raid.get("name", "-"), hp, raid.get("status", "idle"), fmt_age(p["raid_updated"] or p["created_at"])))
                self.party_by_item[iid] = p
            if self.party_by_item:
                first = next(iter(self.party_by_item))
                self.parties_tree.selection_set(first)
            self.show_party()

        # Refresh pending, active, and finished duels.
        def refresh_duels(self):
            names = self.names()
            self.clear_tree(self.duels_tree)
            for d in self.snapshot.get("duels", []):
                iid = str(d["id"])
                self.duels_tree.insert("", "end", iid=iid, values=(d["id"], names.get(d["challenger"], d["challenger"][:8]), names.get(d["target"], d["target"][:8]), d["status"], names.get(d["turn"], d["turn"][:8] if d["turn"] else "-") if d["turn"] else "-", d["hp_challenger"], d["hp_target"], fmt_age(d["updated_at"]), d["log"]))
            children = self.duels_tree.get_children()
            if children:
                self.duels_tree.selection_set(children[0])
            self.show_duel()

        # Refresh tavern message history.
        def refresh_tavern(self):
            self.clear_tree(self.tavern_tree)
            for row in self.snapshot.get("board", []):
                self.tavern_tree.insert("", "end", iid=str(row["id"]), values=(row["id"], row["name"], row["player_key"], fmt_time(row["created_at"]), row["message"]))
            children = self.tavern_tree.get_children()
            if children:
                self.tavern_tree.selection_set(children[0])
            self.show_tavern()

        # Refresh recent player activity.
        def refresh_activity(self):
            names = self.names()
            self.clear_tree(self.activity_tree)
            for row in self.snapshot.get("activity", []):
                self.activity_tree.insert("", "end", iid=str(row["id"]), values=(row["id"], fmt_time(row["created_at"]), names.get(row["player_key"], row["player_key"][:8]), row["player_key"], row["action"], row["detail"]))
            children = self.activity_tree.get_children()
            if children:
                self.activity_tree.selection_set(children[0])
            self.show_activity()

        # Refresh database health and storage details.
        def refresh_database(self):
            h = self.snapshot.get("host", {})
            data = {
                "status": "ok" if self.snapshot.get("ok") else "error",
                "error": self.snapshot.get("error"),
                "path": str(self.db_path),
                "quick_check": self.snapshot.get("quick_check"),
                "meta": self.snapshot.get("meta", {}),
                "counts": self.snapshot.get("counts", {}),
                "files": {"database": h.get("db_size", 0), "wal": h.get("wal_size", 0), "shm": h.get("shm_size", 0)},
            }
            self.put_text(self.database_text, json.dumps(data, indent=2, sort_keys=True))

        # Show the complete selected player record.
        def show_player(self, event=None):
            sel = self.players_tree.selection()
            if not sel or sel[0] not in self.player_by_item:
                self.put_text(self.player_details, "No player selected")
                return
            p = self.player_by_item[sel[0]]
            detail = dict(p)
            detail["updated_at_text"] = fmt_time(p["updated_at"])
            detail["created_text"] = fmt_time(p["created"])
            self.put_text(self.player_details, json.dumps(detail, indent=2, sort_keys=True))

        # Show the selected party and raid history.
        def show_party(self, event=None):
            sel = self.parties_tree.selection()
            if not sel or sel[0] not in self.party_by_item:
                self.put_text(self.party_details, "No party selected")
                return
            p = self.party_by_item[sel[0]]
            events = [e for e in self.snapshot.get("raid_events", []) if e["party_id"] == p["party_id"]][:50]
            detail = dict(p)
            detail["raid_events"] = events
            self.put_text(self.party_details, json.dumps(detail, indent=2, sort_keys=True))

        # Show the selected duel record.
        def show_duel(self, event=None):
            sel = self.duels_tree.selection()
            if not sel:
                self.put_text(self.duel_details, "No duel selected")
                return
            duel_id = int(sel[0])
            d = next((x for x in self.snapshot.get("duels", []) if int(x["id"]) == duel_id), None)
            self.put_text(self.duel_details, json.dumps(d or {}, indent=2, sort_keys=True))

        # Show the selected tavern post.
        def show_tavern(self, event=None):
            sel = self.tavern_tree.selection()
            if not sel:
                self.put_text(self.tavern_details, "No tavern post selected")
                return
            row_id = int(sel[0])
            row = next((x for x in self.snapshot.get("board", []) if int(x["id"]) == row_id), None)
            self.put_text(self.tavern_details, json.dumps(row or {}, indent=2, sort_keys=True))

        # Show the selected activity event.
        def show_activity(self, event=None):
            sel = self.activity_tree.selection()
            if not sel:
                self.put_text(self.activity_details, "No activity selected")
                return
            row_id = int(sel[0])
            row = next((x for x in self.snapshot.get("activity", []) if int(x["id"]) == row_id), None)
            self.put_text(self.activity_details, json.dumps(row or {}, indent=2, sort_keys=True))

    try:
        root = tk.Tk()
    except Exception as exc:
        print(f"Unable to start GUI: {exc}", file=sys.stderr)
        return 2
    Dashboard(root)
    try:
        root.mainloop()
        return 0
    except KeyboardInterrupt:
        return 0


# Read command-line options and start the requested mode.
def main() -> int:
    parser = argparse.ArgumentParser(prog="darktsunami-dashboard")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    db_path = args.db.expanduser().resolve()
    if args.check:
        return check_mode(db_path)
    return run_gui(db_path)


if __name__ == "__main__":
    raise SystemExit(main())
