#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
import random
import sqlite3
import time
from pathlib import Path
from typing import Dict, List, Tuple

GAME_TITLE = "DarkTsunami Keep: LXMF Realms"
GAME_VERSION = "1.0.0"
PAGE_PATH = ":/page/index.mu"
BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = Path(os.environ.get("DARKTSUNAMI_DATA_DIR", str(BASE_DIR / ".darktsunami_keep"))).expanduser()
DB_PATH = Path(os.environ.get("DARKTSUNAMI_DB_PATH", str(DATA_DIR / "game.sqlite3"))).expanduser()
LEGACY_DB_PATH = BASE_DIR / ".ashfall_keep" / "game.sqlite3"
ONLINE_WINDOW = 900
MAX_LOG = 7
MAX_PARTY = 4

CLASSES = {
    "fighter": {"name": "Fighter", "hp": 36, "ac": 15, "attack": 5, "damage": (1, 8, 3), "skill": "Second Wind", "desc": "Armored front-line warrior with a strong self-heal."},
    "rogue": {"name": "Rogue", "hp": 27, "ac": 14, "attack": 6, "damage": (1, 6, 3), "skill": "Backstab", "desc": "Fast striker with brutal critical damage."},
    "ranger": {"name": "Ranger", "hp": 31, "ac": 14, "attack": 5, "damage": (1, 8, 2), "skill": "Hunter's Mark", "desc": "Accurate hunter who weakens dangerous enemies."},
    "mage": {"name": "Mage", "hp": 23, "ac": 12, "attack": 5, "damage": (1, 6, 2), "skill": "Arcane Burst", "desc": "Fragile spellcaster with armor-piercing magic."},
    "cleric": {"name": "Cleric", "hp": 31, "ac": 14, "attack": 4, "damage": (1, 6, 3), "skill": "Radiant Prayer", "desc": "Battle healer who restores health while striking."},
    "barbarian": {"name": "Barbarian", "hp": 42, "ac": 12, "attack": 5, "damage": (1, 10, 3), "skill": "Rage", "desc": "High-health bruiser built for crushing damage."},
}

ROOM_FLAVOR = [
    "Black ash falls through cracks in the ceiling.",
    "Old iron chains sway though the air is still.",
    "A distant bell tolls once from somewhere below.",
    "Pale moss glows around runes carved into the floor.",
    "A cold draft smells of wet stone and dead candles.",
    "A wall bears a warning: THE KEEP REMEMBERS.",
    "Silver beetles scatter from your boots into a drain.",
    "A broken knight statue points deeper into the ruin.",
]

ENEMIES = [
    {"name": "Ash Goblin", "art": "goblin", "hp": 14, "ac": 12, "atk": 3, "dmg": (1, 6, 1), "xp": 18, "gold": (3, 9)},
    {"name": "Grave Rat Pack", "art": "rat", "hp": 17, "ac": 11, "atk": 4, "dmg": (1, 6, 2), "xp": 20, "gold": (1, 6)},
    {"name": "Rustbound Guard", "art": "guard", "hp": 22, "ac": 14, "atk": 4, "dmg": (1, 8, 2), "xp": 27, "gold": (4, 11)},
    {"name": "Lantern Wraith", "art": "wraith", "hp": 19, "ac": 13, "atk": 5, "dmg": (1, 8, 2), "xp": 30, "gold": (5, 13)},
    {"name": "Bone Hexer", "art": "wraith", "hp": 18, "ac": 12, "atk": 5, "dmg": (1, 10, 1), "xp": 32, "gold": (5, 14)},
    {"name": "Cinder Hound", "art": "hound", "hp": 25, "ac": 13, "atk": 5, "dmg": (1, 8, 3), "xp": 34, "gold": (5, 12)},
]

BOSSES = [
    {"name": "The Bell-Warden", "art": "warden", "hp": 52, "ac": 14, "atk": 6, "dmg": (1, 10, 3), "xp": 90, "gold": (20, 35)},
    {"name": "Mara of the Hollow Crown", "art": "queen", "hp": 67, "ac": 15, "atk": 7, "dmg": (2, 6, 3), "xp": 130, "gold": (28, 45)},
    {"name": "The Ash Dragon", "art": "dragon", "hp": 88, "ac": 16, "atk": 8, "dmg": (2, 8, 3), "xp": 200, "gold": (40, 70)},
]

RAID_BOSSES = [
    {"name": "Ghorun, Gate-Eater", "art": "ogre", "hp": 150, "ac": 14, "atk": 6, "dmg": (2, 6, 2)},
    {"name": "The Hollow Colossus", "art": "warden", "hp": 210, "ac": 15, "atk": 7, "dmg": (2, 8, 2)},
    {"name": "Vyrnax the Ash-Wing", "art": "dragon", "hp": 280, "ac": 16, "atk": 8, "dmg": (2, 10, 2)},
]

LOOT = [
    {"name": "Tempered Longsword", "slot": "weapon", "attack": 1, "damage": 1, "ac": 0, "value": 22},
    {"name": "Moonsteel Dagger", "slot": "weapon", "attack": 2, "damage": 0, "ac": 0, "value": 28},
    {"name": "Runed Warhammer", "slot": "weapon", "attack": 0, "damage": 2, "ac": 0, "value": 30},
    {"name": "Ashwood Bow", "slot": "weapon", "attack": 1, "damage": 1, "ac": 0, "value": 24},
    {"name": "Watchman's Mail", "slot": "armor", "attack": 0, "damage": 0, "ac": 2, "value": 30},
    {"name": "Shadowweave Cloak", "slot": "armor", "attack": 1, "damage": 0, "ac": 1, "value": 34},
    {"name": "Dragon-Scale Buckler", "slot": "armor", "attack": 0, "damage": 0, "ac": 3, "value": 48},
]

TRAPS = [
    ("A pressure plate snaps. Darts spit from the walls!", 6, 12),
    ("Rotten boards collapse beneath your boots!", 7, 14),
    ("A violet rune lashes you with cold fire!", 8, 16),
]

PUZZLES = [
    ("I speak without a mouth and answer without ears. What am I?", "echo", 18),
    ("What has keys but opens no locks?", "piano", 20),
    ("What gets wetter the more it dries?", "towel", 22),
]

ASCII = {
    "title": r"""
             /\
            /  \        DARKTSUNAMI KEEP
       /\  / /\ \  /\   LXMF REALMS
      /  \/ /  \ \/  \
     /______/||\______\
        ||  _||_  ||
     ___||_|____|_||___
    /__________________\
""",
    "gate": r"""
        |\                 /|
        | \_______________/ |
        |  _   _   _   _   |
        | | | | | | | | |  |
        | |_| |_| |_| |_|  |
        |      .----.       |
        |     /      \      |
        |____/________\_____|
             |  ||  |
""",
    "goblin": r"""
          ,      ,
         /(.-""-.)\
     |\  \/      \/  /|
     | \ / =.  .= \ / |
      \( \   o\/o   / )/
       \_, '-/  \-' ,_/
         /   \__/   \
""",
    "rat": r"""
       ___     ___
      /   \___/   \
     /  o     o    \
    (      ^        )
     \  ._____.    /
      `-._____.-'
        / /   \ \
""",
    "guard": r"""
          .-===-.
          |  _  |
         /| (_) |\
        / |_____| \
          /| |\
         /_| |_\
        /__| |__\
          /   \
""",
    "wraith": r"""
          .-.
        .'   `.
       /  .-.  \
      |  (   )  |
       \  `-'  /
        `.___.'
        / /|\ \
       /_/ | \_\
          / \
""",
    "hound": r"""
        /\___/\
       /       \
      |  o   o  |
      |    ^    |
       \  '-'  /
       /|     |\
      /_|_____|_\
        / / \ \
""",
    "warden": r"""
           .-====-.
          / ______ \
         | |      | |
         | |  ()  | |
        /| |______| |\
       / |___/||\___| \
          _/ || \_
         /___||___\
""",
    "queen": r"""
           \  |  /
         '. \ | / .'
       .---.\|/.---.
      /     ( )     \
     |      /|\      |
     |     / | \     |
      \___/  |  \___/
          __/ \__
""",
    "dragon": r"""
              / \  //\
       |\___/|      /   \//  .\
       /O  O  \__  /    //  | \ \ 
      /     /  \/_/    //   |  \  \
      @___@'    \/_   //    |   \   \
         |       \/_ //     |    \    \
         |        \///      |     \     \
        _|_ /   )  //       |      \     _\
       '/,_ _ _/  ( ; -.    |    _ _\.-~        .-~~~^-.
""",
    "ogre": r"""
          __,='`````'=/__
         '//  (o) \(o) \ `'         _,-,
         //|     ,_)   (`\      ,-'`_,-\
       ,-~~~\  `'==='  /-,      \==''''' 
      /        `----'     `\     \
     /                      `\.__/ \
    /                        `    |
""",
    "chest": r"""
          __________
         /_________/|
        |  _____  | |
        | |  _  | | |
        | | |_| | | |
        | |_____| | /
        |_________|/
""",
    "merchant": r"""
          .------.
         / .----. \
        | |      | |
        | | .--. | |
         \ \____/ /
          '------'
          /|    |\
        _/ |____| \_
       /___/    \___\
""",
    "runes": r"""
       +----------------+
       |  /\  <>  /\    |
       | <  > /\ <  >   |
       |  \/ <  > \/    |
       |     \/         |
       +----------------+
""",
    "tavern": r"""
       ___________________
      /__________________/|
      |  _   TAVERN   _  ||
      | |_|           |_| ||
      |      .----.       ||
      |     /      \      ||
      |____/________\_____||
          |  _||_  |
""",
    "party": r"""
          (  )   (   )  )
           ) (   )  (  (
           ( )  (    ) )
           _____________
          <_____________> ___
          |             |/ _ \
          |   PARTY     | | | |
          |_____________|\___/
""",
    "arena": r"""
       |\             /|
       | \___________/ |
       |   \   |   /   |
       |----\--+--/----|
       |     \ | /     |
       |      \|/      |
       |_______V_______|
""",
}


def now_ts() -> int:
    return int(time.time())


def clamp(n: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, n))


def dice(count: int, sides: int, bonus: int = 0) -> int:
    return sum(random.randint(1, sides) for _ in range(count)) + bonus


def safe_text(value: str, max_len: int = 28) -> str:
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-'!?.,"
    value = "".join(c for c in (value or "").strip() if c in allowed)
    return value[:max_len] or "Nameless"


def safe_message(value: str, max_len: int = 96) -> str:
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-'!?.,:;()"
    return "".join(c for c in (value or "").strip() if c in allowed)[:max_len]


def get_var(name: str, default: str = "") -> str:
    return os.environ.get("var_" + name, os.environ.get(name, default))


def get_field(name: str, default: str = "") -> str:
    return os.environ.get("field_" + name, os.environ.get(name, default))


def lxmf_address(identity_hex: str) -> str:
    identity_hash = bytes.fromhex(identity_hex)
    if len(identity_hash) != 16:
        raise ValueError("identity hash must be 16 bytes")
    name_hash = hashlib.sha256(b"lxmf.delivery").digest()[:10]
    return hashlib.sha256(name_hash + identity_hash).digest()[:16].hex()


def player_identity() -> Tuple[str | None, str | None]:
    identity = os.environ.get("remote_identity", "").strip().lower()
    if len(identity) == 32:
        try:
            return lxmf_address(identity), identity
        except ValueError:
            pass
    test_identity = os.environ.get("DARKTSUNAMI_TEST_IDENTITY", "").strip().lower()
    if len(test_identity) == 32:
        try:
            return lxmf_address(test_identity), test_identity
        except ValueError:
            pass
    return None, None


def migrate_legacy_database() -> None:
    if DB_PATH.exists() or not LEGACY_DB_PATH.exists():
        return
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    src = sqlite3.connect(f"file:{LEGACY_DB_PATH}?mode=ro", uri=True, timeout=8.0)
    dst = sqlite3.connect(DB_PATH, timeout=8.0)
    try:
        src.backup(dst)
    finally:
        dst.close()
        src.close()


def init_db() -> sqlite3.Connection:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    migrate_legacy_database()
    db = sqlite3.connect(DB_PATH, timeout=8.0)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA busy_timeout=8000")
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=NORMAL")
    db.execute("PRAGMA wal_autocheckpoint=1000")
    db.execute("CREATE TABLE IF NOT EXISTS players (player_key TEXT PRIMARY KEY, state_json TEXT NOT NULL, updated_at INTEGER NOT NULL)")
    cols = {r[1] for r in db.execute("PRAGMA table_info(players)").fetchall()}
    if "identity_hash" not in cols:
        db.execute("ALTER TABLE players ADD COLUMN identity_hash TEXT")
    db.execute("CREATE TABLE IF NOT EXISTS scores (player_key TEXT PRIMARY KEY, name TEXT NOT NULL, level INTEGER NOT NULL, deepest INTEGER NOT NULL, victories INTEGER NOT NULL, score INTEGER NOT NULL, updated_at INTEGER NOT NULL)")
    db.execute("CREATE TABLE IF NOT EXISTS board (id INTEGER PRIMARY KEY AUTOINCREMENT, player_key TEXT NOT NULL, name TEXT NOT NULL, message TEXT NOT NULL, created_at INTEGER NOT NULL)")
    db.execute("CREATE TABLE IF NOT EXISTS parties (party_id TEXT PRIMARY KEY, leader TEXT NOT NULL, name TEXT NOT NULL, created_at INTEGER NOT NULL)")
    db.execute("CREATE TABLE IF NOT EXISTS party_members (player_key TEXT PRIMARY KEY, party_id TEXT NOT NULL, joined_at INTEGER NOT NULL)")
    db.execute("CREATE TABLE IF NOT EXISTS raid_state (party_id TEXT PRIMARY KEY, state_json TEXT NOT NULL, updated_at INTEGER NOT NULL)")
    db.execute("CREATE TABLE IF NOT EXISTS raid_events (id INTEGER PRIMARY KEY AUTOINCREMENT, party_id TEXT NOT NULL, player_key TEXT NOT NULL, text TEXT NOT NULL, created_at INTEGER NOT NULL)")
    db.execute("CREATE TABLE IF NOT EXISTS raid_rewards (party_id TEXT NOT NULL, player_key TEXT NOT NULL, xp INTEGER NOT NULL, gold INTEGER NOT NULL, claimed INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(party_id,player_key))")
    db.execute("CREATE TABLE IF NOT EXISTS raid_actions (party_id TEXT NOT NULL, player_key TEXT NOT NULL, skill_used INTEGER NOT NULL DEFAULT 0, damage INTEGER NOT NULL DEFAULT 0, healing INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(party_id,player_key))")
    db.execute("CREATE TABLE IF NOT EXISTS duels (id INTEGER PRIMARY KEY AUTOINCREMENT, challenger TEXT NOT NULL, target TEXT NOT NULL, status TEXT NOT NULL, turn TEXT, hp_challenger INTEGER NOT NULL DEFAULT 0, hp_target INTEGER NOT NULL DEFAULT 0, log TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)")
    db.execute("CREATE TABLE IF NOT EXISTS activity (id INTEGER PRIMARY KEY AUTOINCREMENT, player_key TEXT NOT NULL, action TEXT NOT NULL, detail TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL)")
    db.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    db.execute("CREATE INDEX IF NOT EXISTS idx_players_updated ON players(updated_at)")
    db.execute("CREATE INDEX IF NOT EXISTS idx_board_created ON board(created_at)")
    db.execute("CREATE INDEX IF NOT EXISTS idx_party_members_party ON party_members(party_id)")
    db.execute("CREATE INDEX IF NOT EXISTS idx_raid_events_party ON raid_events(party_id,id)")
    db.execute("CREATE INDEX IF NOT EXISTS idx_duels_status_updated ON duels(status,updated_at)")
    db.execute("CREATE INDEX IF NOT EXISTS idx_activity_created ON activity(created_at)")
    db.execute("INSERT INTO meta(key,value) VALUES('game_title',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (GAME_TITLE,))
    db.execute("INSERT INTO meta(key,value) VALUES('game_version',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (GAME_VERSION,))
    db.execute("INSERT INTO meta(key,value) VALUES('schema_version','2') ON CONFLICT(key) DO UPDATE SET value=excluded.value")
    legacy = db.execute("SELECT player_key,state_json FROM players WHERE player_key LIKE 'id:%'").fetchall()
    for row in legacy:
        old = row["player_key"]
        ident = old[3:]
        try:
            new = lxmf_address(ident)
        except ValueError:
            continue
        if db.execute("SELECT 1 FROM players WHERE player_key=?", (new,)).fetchone():
            db.execute("DELETE FROM players WHERE player_key=?", (old,))
            db.execute("DELETE FROM scores WHERE player_key=?", (old,))
            continue
        try:
            state = json.loads(row["state_json"]); state["address"] = new
            payload = json.dumps(state, separators=(",", ":"), sort_keys=True)
        except Exception:
            payload = row["state_json"]
        db.execute("UPDATE players SET player_key=?,state_json=?,identity_hash=? WHERE player_key=?", (new,payload,ident,old))
        db.execute("UPDATE scores SET player_key=? WHERE player_key=?", (new,old))
    for prefix in ("link:%", "local:%"):
        db.execute("DELETE FROM players WHERE player_key LIKE ?", (prefix,))
        db.execute("DELETE FROM scores WHERE player_key LIKE ?", (prefix,))
    db.commit()
    return db


def new_state(name: str, cls: str, address: str) -> Dict:
    c = CLASSES[cls]
    return {
        "address": address,
        "name": safe_text(name),
        "class": cls,
        "level": 1,
        "xp": 0,
        "gold": 12,
        "hp": c["hp"],
        "max_hp": c["hp"],
        "potions": 2,
        "rooms": 0,
        "deepest": 0,
        "victories": 0,
        "deaths": 0,
        "duel_wins": 0,
        "score": 0,
        "run_seed": random.randint(100000, 999999999),
        "room_id": 0,
        "room_type": "crossroads",
        "enemy": None,
        "guarding": False,
        "skill_used": False,
        "weapon": None,
        "armor": None,
        "pending_loot": None,
        "puzzle": None,
        "log": ["You arrive at DarkTsunami Keep as thunder rolls over the moor."],
        "created": now_ts(),
    }


def load_state(db: sqlite3.Connection, key: str) -> Dict | None:
    row = db.execute("SELECT state_json FROM players WHERE player_key=?", (key,)).fetchone()
    if not row:
        return None
    try:
        state = json.loads(row["state_json"])
        state["address"] = key
        state.setdefault("duel_wins", 0)
        return state
    except Exception:
        return None


def save_state(db: sqlite3.Connection, key: str, identity: str, s: Dict) -> None:
    s["address"] = key
    s["hp"] = int(clamp(int(s.get("hp", 0)), 0, int(s.get("max_hp", 1))))
    payload = json.dumps(s, separators=(",", ":"), sort_keys=True)
    db.execute(
        "INSERT INTO players(player_key,state_json,updated_at,identity_hash) VALUES(?,?,?,?) ON CONFLICT(player_key) DO UPDATE SET state_json=excluded.state_json,updated_at=excluded.updated_at,identity_hash=excluded.identity_hash",
        (key, payload, now_ts(), identity),
    )
    db.execute(
        "INSERT INTO scores(player_key,name,level,deepest,victories,score,updated_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(player_key) DO UPDATE SET name=excluded.name,level=excluded.level,deepest=excluded.deepest,victories=excluded.victories,score=excluded.score,updated_at=excluded.updated_at",
        (key, s["name"], s["level"], s["deepest"], s["victories"], s["score"], now_ts()),
    )
    db.commit()


def add_log(s: Dict, msg: str) -> None:
    log = s.setdefault("log", [])
    log.insert(0, msg)
    del log[MAX_LOG:]


def record_activity(db: sqlite3.Connection, key: str, action: str, detail: str = "") -> None:
    if action in ("", "view"):
        return
    db.execute("INSERT INTO activity(player_key,action,detail,created_at) VALUES(?,?,?,?)", (key, safe_text(action, 40), safe_message(detail, 120), now_ts()))
    db.execute("DELETE FROM activity WHERE id NOT IN (SELECT id FROM activity ORDER BY id DESC LIMIT 2000)")


def xp_needed(level: int) -> int:
    return 55 + (level - 1) * 45


def maybe_level(s: Dict) -> None:
    while s["xp"] >= xp_needed(s["level"]):
        s["xp"] -= xp_needed(s["level"])
        s["level"] += 1
        hp_gain = 7 if s["class"] in ("fighter", "barbarian") else 5
        s["max_hp"] += hp_gain
        s["hp"] = s["max_hp"]
        s["potions"] += 1
        add_log(s, f"LEVEL UP! You reach level {s['level']} and gain a potion.")


def gear_bonus(s: Dict, field: str) -> int:
    return sum(int((s.get(slot) or {}).get(field, 0)) for slot in ("weapon", "armor"))


def attack_bonus(s: Dict) -> int:
    return CLASSES[s["class"]]["attack"] + (s["level"] - 1) // 2 + gear_bonus(s, "attack")


def armor_class(s: Dict) -> int:
    return CLASSES[s["class"]]["ac"] + (s["level"] - 1) // 4 + gear_bonus(s, "ac")


def damage_roll(s: Dict) -> int:
    c, sides, bonus = CLASSES[s["class"]]["damage"]
    return max(1, dice(c, sides, bonus + gear_bonus(s, "damage") + (s["level"] - 1) // 3))


def scaled_enemy(template: Dict, depth: int, boss: bool = False) -> Dict:
    tier = max(0, (depth - 1) // 5)
    hp_mult = 1.0 + 0.16 * tier + (0.10 if boss else 0)
    return {
        "name": template["name"], "art": template.get("art", "guard"),
        "hp": int(template["hp"] * hp_mult), "max_hp": int(template["hp"] * hp_mult),
        "ac": template["ac"] + tier // 2, "atk": template["atk"] + tier // 2,
        "dmg": list(template["dmg"]), "xp": int(template["xp"] * (1 + 0.12 * tier)),
        "gold_min": template["gold"][0] + tier, "gold_max": template["gold"][1] + tier * 2,
        "boss": boss, "weakened": 0,
    }


def deterministic_rng(s: Dict, salt: str) -> random.Random:
    raw = f"{s['run_seed']}:{s['rooms']}:{s['room_id']}:{salt}".encode()
    return random.Random(int(hashlib.sha256(raw).hexdigest()[:16], 16))


def choose_next_room(s: Dict, route: str) -> str:
    if (s["rooms"] + 1) % 10 == 0:
        return "boss"
    tables = {
        "torch": [("combat", 35), ("treasure", 22), ("trap", 13), ("shrine", 12), ("merchant", 9), ("puzzle", 9)],
        "stairs": [("combat", 48), ("treasure", 18), ("trap", 15), ("shrine", 7), ("merchant", 5), ("puzzle", 7)],
        "whisper": [("combat", 30), ("treasure", 19), ("trap", 16), ("shrine", 10), ("merchant", 8), ("puzzle", 17)],
    }
    roll = deterministic_rng(s, "route:" + route).randint(1, 100)
    total = 0
    for kind, weight in tables.get(route, tables["torch"]):
        total += weight
        if roll <= total:
            return kind
    return "combat"


def enter_room(s: Dict, route: str) -> None:
    kind = choose_next_room(s, route)
    s["rooms"] += 1
    s["deepest"] = max(s["deepest"], s["rooms"])
    s["room_id"] += 1
    s["room_type"] = kind
    s["enemy"] = None
    s["pending_loot"] = None
    s["puzzle"] = None
    s["guarding"] = False
    s["skill_used"] = False
    flavor = deterministic_rng(s, "flavor").choice(ROOM_FLAVOR)
    if kind == "combat":
        s["enemy"] = scaled_enemy(deterministic_rng(s, "enemy").choice(ENEMIES), s["rooms"])
        add_log(s, f"{flavor} A {s['enemy']['name']} blocks your path.")
    elif kind == "boss":
        idx = min(len(BOSSES) - 1, max(0, s["rooms"] // 10 - 1))
        s["enemy"] = scaled_enemy(BOSSES[idx], s["rooms"], True)
        add_log(s, f"BOSS CHAMBER: {s['enemy']['name']} awaits. {flavor}")
    elif kind == "treasure":
        item = dict(deterministic_rng(s, "loot").choice(LOOT))
        quality = max(0, s["rooms"] // 10)
        if quality and deterministic_rng(s, "quality").random() < 0.55:
            if item["slot"] == "armor": item["ac"] += min(2, quality)
            else: item["damage"] += min(2, quality)
            item["name"] = "Fine " + item["name"]
        s["pending_loot"] = item
        add_log(s, f"{flavor} A coffer opens. Inside: {item['name']}.")
    elif kind == "trap":
        desc, lo, hi = deterministic_rng(s, "trap").choice(TRAPS)
        save = random.randint(1, 20) + attack_bonus(s)
        dc = 13 + s["rooms"] // 8
        dmg = random.randint(lo, hi)
        if save >= dc: dmg = max(1, dmg // 2)
        s["hp"] -= dmg
        add_log(s, f"{desc} You take {dmg} damage.")
        if s["hp"] > 0: s["room_type"] = "crossroads"
    elif kind == "shrine":
        heal = max(6, s["max_hp"] // 3)
        s["hp"] = min(s["max_hp"], s["hp"] + heal)
        if random.random() < 0.35:
            s["potions"] += 1
            add_log(s, f"{flavor} A shrine restores {heal} HP and grants a potion.")
        else:
            add_log(s, f"{flavor} A shrine restores {heal} HP.")
        s["room_type"] = "crossroads"
    elif kind == "merchant":
        add_log(s, f"{flavor} A masked peddler unfolds a shop from a red suitcase.")
    elif kind == "puzzle":
        q, answer, reward = deterministic_rng(s, "puzzle").choice(PUZZLES)
        s["puzzle"] = {"question": q, "answer": answer, "reward": reward + s["rooms"]}
        add_log(s, f"{flavor} A sealed door presents a riddle.")


def enemy_turn(s: Dict) -> None:
    e = s.get("enemy")
    if not e or e["hp"] <= 0 or s["hp"] <= 0: return
    roll = random.randint(1, 20)
    atk = e["atk"] - (2 if e.get("weakened", 0) > 0 else 0)
    target = armor_class(s) + (3 if s.get("guarding") else 0)
    s["guarding"] = False
    if e.get("weakened", 0) > 0: e["weakened"] -= 1
    if roll == 1:
        add_log(s, f"{e['name']} attacks and misses badly.")
    elif roll == 20 or roll + atk >= target:
        c, sides, bonus = e["dmg"]
        dmg = dice(c, sides, bonus) + (dice(c, sides) if roll == 20 else 0)
        s["hp"] -= dmg
        add_log(s, f"{e['name']} {'CRITS' if roll == 20 else 'hits'} you for {dmg} damage.")
    else:
        add_log(s, f"{e['name']} misses you.")


def defeat_enemy(s: Dict) -> None:
    e = s.get("enemy")
    if not e or e["hp"] > 0: return
    gold = random.randint(e["gold_min"], e["gold_max"])
    s["gold"] += gold
    s["xp"] += e["xp"]
    s["score"] += e["xp"] * (2 if e.get("boss") else 1) + gold
    add_log(s, f"VICTORY! {e['name']} falls. +{e['xp']} XP, +{gold} gold.")
    boss = e.get("boss", False)
    s["enemy"] = None
    s["room_type"] = "crossroads"
    if boss:
        s["victories"] += 1
        s["score"] += 100 * s["victories"]
        s["potions"] += 1
        add_log(s, "An ancient seal breaks and a deeper stair opens.")
    elif random.random() < 0.16:
        s["pending_loot"] = dict(random.choice(LOOT))
        s["room_type"] = "treasure"
        add_log(s, f"The foe carried {s['pending_loot']['name']}.")
    maybe_level(s)


def handle_death(s: Dict) -> None:
    if s["hp"] > 0: return
    lost = min(s["gold"], max(3, s["gold"] // 4))
    s["gold"] -= lost
    s["deaths"] += 1
    s["rooms"] = 0
    s["room_id"] = 0
    s["run_seed"] = random.randint(100000, 999999999)
    s["enemy"] = None
    s["pending_loot"] = None
    s["puzzle"] = None
    s["room_type"] = "crossroads"
    s["hp"] = max(1, s["max_hp"] // 2)
    s["potions"] = max(1, s["potions"])
    add_log(s, f"The Ferryman drags you back to the gate and takes {lost} gold.")


def do_attack(s: Dict, power: bool = False) -> None:
    e = s.get("enemy")
    if not e: return
    roll = random.randint(1, 20)
    total = roll + attack_bonus(s) - (2 if power else 0)
    if roll == 1:
        add_log(s, f"You stumble and miss {e['name']}.")
    elif roll == 20 or total >= e["ac"]:
        dmg = damage_roll(s) + (4 + s["level"] // 2 if power else 0)
        if roll == 20: dmg += damage_roll(s)
        e["hp"] -= dmg
        add_log(s, f"{'CRITICAL! ' if roll == 20 else ''}You hit {e['name']} for {dmg} damage.")
    else:
        add_log(s, f"Your attack misses {e['name']}.")
    defeat_enemy(s)
    enemy_turn(s)
    handle_death(s)


def do_guard(s: Dict) -> None:
    if not s.get("enemy"): return
    s["guarding"] = True
    heal = 1 + s["level"] // 3
    s["hp"] = min(s["max_hp"], s["hp"] + heal)
    add_log(s, f"You guard (+3 AC) and recover {heal} HP.")
    enemy_turn(s)
    handle_death(s)


def do_skill(s: Dict) -> None:
    e = s.get("enemy")
    if not e: return
    if s.get("skill_used"):
        add_log(s, "Your class ability is already spent this fight.")
        return
    s["skill_used"] = True
    cls = s["class"]
    if cls == "fighter":
        heal = dice(1, 10, 4 + s["level"])
        s["hp"] = min(s["max_hp"], s["hp"] + heal)
        add_log(s, f"SECOND WIND restores {heal} HP.")
    elif cls == "rogue":
        roll = random.randint(1, 20) + attack_bonus(s) + 2
        if roll >= e["ac"]:
            dmg = damage_roll(s) + dice(2, 6, s["level"] // 2)
            if random.random() < 0.30: dmg += dice(2, 6)
            e["hp"] -= dmg
            add_log(s, f"BACKSTAB deals {dmg} damage.")
        else: add_log(s, "BACKSTAB misses.")
    elif cls == "ranger":
        dmg = dice(1, 8, 3 + s["level"] // 2)
        e["hp"] -= dmg
        e["weakened"] = 2
        add_log(s, f"HUNTER'S MARK deals {dmg}; foe weakened.")
    elif cls == "mage":
        dmg = dice(2, 8, 3 + s["level"])
        if random.random() < 0.20: dmg += dice(2, 8)
        e["hp"] -= dmg
        add_log(s, f"ARCANE BURST deals {dmg} armor-piercing damage.")
    elif cls == "cleric":
        heal = dice(1, 8, 3 + s["level"])
        dmg = dice(1, 6, 2 + s["level"] // 2)
        s["hp"] = min(s["max_hp"], s["hp"] + heal)
        e["hp"] -= dmg
        add_log(s, f"RADIANT PRAYER heals {heal} and deals {dmg} damage.")
    elif cls == "barbarian":
        dmg = damage_roll(s) + dice(1, 10, 4 + s["level"])
        e["hp"] -= dmg
        add_log(s, f"RAGE crashes into the foe for {dmg} damage.")
    defeat_enemy(s)
    enemy_turn(s)
    handle_death(s)


def do_potion(s: Dict) -> None:
    if s["potions"] <= 0:
        add_log(s, "You have no healing potions.")
        return
    if s["hp"] >= s["max_hp"]:
        add_log(s, "You are already at full health.")
        return
    s["potions"] -= 1
    heal = dice(2, 6, 4 + s["level"])
    s["hp"] = min(s["max_hp"], s["hp"] + heal)
    add_log(s, f"You drink a potion and restore {heal} HP.")
    if s.get("enemy"):
        enemy_turn(s)
        handle_death(s)


def do_flee(s: Dict) -> None:
    e = s.get("enemy")
    if not e: return
    if e.get("boss"):
        add_log(s, "The boss seals the chamber. You cannot flee.")
        return
    if random.random() < 0.55:
        s["enemy"] = None
        s["room_type"] = "crossroads"
        add_log(s, "You escape into a side passage.")
    else:
        add_log(s, "You fail to escape.")
        enemy_turn(s)
        handle_death(s)


def equip_pending(s: Dict) -> None:
    item = s.get("pending_loot")
    if not item: return
    old = s.get(item["slot"])
    s[item["slot"]] = item
    s["pending_loot"] = None
    s["room_type"] = "crossroads"
    if old:
        s["gold"] += max(1, old.get("value", 0) // 3)
        add_log(s, f"You equip {item['name']} and salvage {old['name']}.")
    else: add_log(s, f"You equip {item['name']}.")


def sell_pending(s: Dict) -> None:
    item = s.get("pending_loot")
    if not item: return
    s["gold"] += item["value"]
    s["pending_loot"] = None
    s["room_type"] = "crossroads"
    add_log(s, f"You stash the item for sale and gain {item['value']} gold.")


def merchant_buy(s: Dict, item: str) -> None:
    costs = {"potion": 10 + s["level"] * 2, "heal": 8 + s["level"], "mystery": 28 + s["level"] * 3}
    cost = costs.get(item, 999999)
    if s["gold"] < cost:
        add_log(s, "The peddler taps the price tag. You need more gold.")
        return
    s["gold"] -= cost
    if item == "potion":
        s["potions"] += 1
        add_log(s, "You buy a healing draught.")
    elif item == "heal":
        s["hp"] = s["max_hp"]
        add_log(s, "The restorative tonic returns you to full health.")
    elif item == "mystery":
        s["pending_loot"] = dict(random.choice(LOOT))
        s["room_type"] = "treasure"
        add_log(s, f"The bundle contains {s['pending_loot']['name']}.")


def solve_puzzle(s: Dict, answer: str) -> None:
    p = s.get("puzzle")
    if not p: return
    if safe_text(answer, 24).lower() == p["answer"]:
        reward = p["reward"]
        s["gold"] += reward
        s["score"] += reward * 2
        s["room_type"] = "crossroads"
        s["puzzle"] = None
        add_log(s, f"The runes fade. Correct! You find {reward} gold.")
    else:
        dmg = random.randint(3, 8 + s["level"])
        s["hp"] -= dmg
        add_log(s, f"Wrong. The ward burns you for {dmg} damage.")
        handle_death(s)


def rest_at_gate(s: Dict) -> None:
    if s["rooms"] != 0 or s["enemy"]: return
    if s["gold"] < 5:
        add_log(s, "You need 5 gold for a bunk at the roadside inn.")
        return
    s["gold"] -= 5
    s["hp"] = s["max_hp"]
    add_log(s, "A hot meal and a narrow bunk restore you to full health.")


def abandon_run(s: Dict) -> None:
    if s["enemy"]: return
    s["rooms"] = 0
    s["room_id"] = 0
    s["run_seed"] = random.randint(100000, 999999999)
    s["room_type"] = "crossroads"
    add_log(s, "You return safely to the gate. The keep shifts behind you.")


def reset_character(db: sqlite3.Connection, key: str) -> None:
    party = db.execute("SELECT party_id FROM party_members WHERE player_key=?", (key,)).fetchone()
    db.execute("DELETE FROM players WHERE player_key=?", (key,))
    db.execute("DELETE FROM scores WHERE player_key=?", (key,))
    db.execute("DELETE FROM party_members WHERE player_key=?", (key,))
    if party: cleanup_party(db, party["party_id"])
    db.commit()


def party_for(db: sqlite3.Connection, key: str) -> sqlite3.Row | None:
    return db.execute("SELECT p.* FROM parties p JOIN party_members m ON p.party_id=m.party_id WHERE m.player_key=?", (key,)).fetchone()


def party_members(db: sqlite3.Connection, party_id: str) -> List[sqlite3.Row]:
    return db.execute(
        "SELECT m.player_key,s.name,s.level,p.updated_at FROM party_members m LEFT JOIN scores s ON s.player_key=m.player_key LEFT JOIN players p ON p.player_key=m.player_key WHERE m.party_id=? ORDER BY m.joined_at",
        (party_id,),
    ).fetchall()


def make_party(db: sqlite3.Connection, key: str, name: str) -> str:
    existing = party_for(db, key)
    if existing: return existing["party_id"]
    party_id = hashlib.sha256(f"{key}:{time.time_ns()}".encode()).hexdigest()[:8]
    pname = safe_text(name, 24)
    if pname == "Nameless": pname = "DarkTide Company"
    db.execute("INSERT INTO parties(party_id,leader,name,created_at) VALUES(?,?,?,?)", (party_id, key, pname, now_ts()))
    db.execute("INSERT INTO party_members(player_key,party_id,joined_at) VALUES(?,?,?)", (key, party_id, now_ts()))
    db.commit()
    return party_id


def join_party(db: sqlite3.Connection, key: str, party_id: str) -> str:
    if party_for(db, key): return "You are already in a party."
    party = db.execute("SELECT * FROM parties WHERE party_id=?", (party_id,)).fetchone()
    if not party: return "That party no longer exists."
    count = db.execute("SELECT COUNT(*) FROM party_members WHERE party_id=?", (party_id,)).fetchone()[0]
    if count >= MAX_PARTY: return "That party is full."
    db.execute("INSERT OR REPLACE INTO party_members(player_key,party_id,joined_at) VALUES(?,?,?)", (key, party_id, now_ts()))
    db.commit()
    return f"You joined {party['name']}."


def cleanup_party(db: sqlite3.Connection, party_id: str) -> None:
    members = db.execute("SELECT player_key FROM party_members WHERE party_id=? ORDER BY joined_at", (party_id,)).fetchall()
    if not members:
        db.execute("DELETE FROM parties WHERE party_id=?", (party_id,))
        db.execute("DELETE FROM raid_state WHERE party_id=?", (party_id,))
        db.execute("DELETE FROM raid_actions WHERE party_id=?", (party_id,))
    else:
        party = db.execute("SELECT leader FROM parties WHERE party_id=?", (party_id,)).fetchone()
        if party and party["leader"] not in [r["player_key"] for r in members]:
            db.execute("UPDATE parties SET leader=? WHERE party_id=?", (members[0]["player_key"], party_id))


def leave_party(db: sqlite3.Connection, key: str) -> str:
    party = party_for(db, key)
    if not party: return "You are not in a party."
    db.execute("DELETE FROM party_members WHERE player_key=?", (key,))
    cleanup_party(db, party["party_id"])
    db.commit()
    return "You leave the party."


def start_raid(db: sqlite3.Connection, party_id: str) -> Dict:
    members = party_members(db, party_id)
    levels = [int(r["level"] or 1) for r in members]
    avg = max(1, sum(levels) // max(1, len(levels)))
    template = RAID_BOSSES[min(len(RAID_BOSSES) - 1, (avg - 1) // 4)]
    mult = 1.0 + 0.45 * max(0, len(members) - 1) + 0.12 * max(0, avg - 1)
    hp = int(template["hp"] * mult)
    raid = {"name": template["name"], "art": template["art"], "hp": hp, "max_hp": hp, "ac": template["ac"] + (avg - 1) // 4, "atk": template["atk"] + (avg - 1) // 3, "dmg": list(template["dmg"]), "status": "active", "round": 1, "started": now_ts(), "victory_at": 0}
    db.execute("INSERT INTO raid_state(party_id,state_json,updated_at) VALUES(?,?,?) ON CONFLICT(party_id) DO UPDATE SET state_json=excluded.state_json,updated_at=excluded.updated_at", (party_id, json.dumps(raid, separators=(",", ":")), now_ts()))
    db.execute("DELETE FROM raid_actions WHERE party_id=?", (party_id,))
    db.execute("DELETE FROM raid_rewards WHERE party_id=?", (party_id,))
    db.execute("DELETE FROM raid_events WHERE party_id=?", (party_id,))
    db.execute("INSERT INTO raid_events(party_id,player_key,text,created_at) VALUES(?,?,?,?)", (party_id, "system", f"{raid['name']} emerges from the ash!", now_ts()))
    db.commit()
    return raid


def load_raid(db: sqlite3.Connection, party_id: str) -> Dict | None:
    row = db.execute("SELECT state_json FROM raid_state WHERE party_id=?", (party_id,)).fetchone()
    if not row: return None
    try: return json.loads(row["state_json"])
    except Exception: return None


def save_raid(db: sqlite3.Connection, party_id: str, raid: Dict) -> None:
    db.execute("UPDATE raid_state SET state_json=?,updated_at=? WHERE party_id=?", (json.dumps(raid, separators=(",", ":")), now_ts(), party_id))


def raid_event(db: sqlite3.Connection, party_id: str, key: str, text: str) -> None:
    db.execute("INSERT INTO raid_events(party_id,player_key,text,created_at) VALUES(?,?,?,?)", (party_id, key, text, now_ts()))


def raid_counterattack(s: Dict, raid: Dict) -> str:
    roll = random.randint(1, 20)
    if roll == 1 or (roll != 20 and roll + raid["atk"] < armor_class(s)):
        return f"{raid['name']} misses {s['name']}."
    c, sides, bonus = raid["dmg"]
    dmg = dice(c, sides, bonus) + (dice(c, sides) if roll == 20 else 0)
    s["hp"] -= dmg
    if s["hp"] <= 0:
        s["hp"] = 1
        return f"{raid['name']} knocks {s['name']} down for {dmg}; allies drag them back up at 1 HP."
    return f"{raid['name']} hits {s['name']} for {dmg}."


def finish_raid(db: sqlite3.Connection, party_id: str, raid: Dict, finisher: str) -> None:
    if raid.get("status") == "defeated": return
    raid["status"] = "defeated"
    raid["hp"] = 0
    raid["victory_at"] = now_ts()
    members = party_members(db, party_id)
    for m in members:
        lvl = int(m["level"] or 1)
        db.execute("INSERT OR REPLACE INTO raid_rewards(party_id,player_key,xp,gold,claimed) VALUES(?,?,?,?,0)", (party_id, m["player_key"], 70 + lvl * 12, 24 + lvl * 4))
    raid_event(db, party_id, finisher, f"{raid['name']} falls! Rewards are granted to the whole party.")


def raid_action(db: sqlite3.Connection, key: str, s: Dict, mode: str) -> str:
    party = party_for(db, key)
    if not party: return "Join a party before entering a raid."
    party_id = party["party_id"]
    db.execute("BEGIN IMMEDIATE")
    raid = load_raid(db, party_id)
    if not raid or raid.get("status") != "active":
        db.rollback()
        return "There is no active raid boss."
    row = db.execute("SELECT * FROM raid_actions WHERE party_id=? AND player_key=?", (party_id, key)).fetchone()
    skill_used = bool(row["skill_used"]) if row else False
    damage = int(row["damage"]) if row else 0
    healing = int(row["healing"]) if row else 0
    text = ""
    dealt = 0
    healed = 0
    if mode == "attack":
        roll = random.randint(1, 20)
        if roll == 20 or (roll != 1 and roll + attack_bonus(s) >= raid["ac"]):
            dealt = damage_roll(s) + (damage_roll(s) if roll == 20 else 0)
            raid["hp"] -= dealt
            text = f"{s['name']} {'CRITS' if roll == 20 else 'hits'} for {dealt}."
        else: text = f"{s['name']} attacks and misses."
    elif mode == "skill":
        if skill_used:
            db.rollback()
            return "Your raid ability is already spent for this boss."
        skill_used = True
        cls = s["class"]
        if cls == "cleric":
            healed = dice(2, 8, 4 + s["level"])
            s["hp"] = min(s["max_hp"], s["hp"] + healed)
            dealt = dice(1, 8, s["level"])
            raid["hp"] -= dealt
            text = f"{s['name']} invokes Radiant Prayer: {dealt} damage, {healed} healing."
        elif cls == "fighter":
            healed = dice(1, 10, 5 + s["level"])
            s["hp"] = min(s["max_hp"], s["hp"] + healed)
            dealt = damage_roll(s) + 4
            raid["hp"] -= dealt
            text = f"{s['name']} surges forward: {dealt} damage, {healed} healing."
        elif cls == "rogue":
            dealt = damage_roll(s) + dice(3, 6, s["level"])
            raid["hp"] -= dealt
            text = f"{s['name']} finds a weak point for {dealt} damage."
        elif cls == "ranger":
            dealt = dice(2, 8, 5 + s["level"])
            raid["hp"] -= dealt
            raid["atk"] = max(1, raid["atk"] - 1)
            text = f"{s['name']} marks the beast for {dealt} and lowers its attack."
        elif cls == "mage":
            dealt = dice(3, 8, 5 + s["level"])
            raid["hp"] -= dealt
            text = f"{s['name']} unleashes an arcane storm for {dealt} damage."
        else:
            dealt = damage_roll(s) + dice(2, 10, 4 + s["level"])
            raid["hp"] -= dealt
            text = f"{s['name']} enters a raid-fury for {dealt} damage."
    elif mode == "potion":
        if s["potions"] <= 0:
            db.rollback()
            return "You have no potions."
        s["potions"] -= 1
        healed = dice(2, 6, 5 + s["level"])
        s["hp"] = min(s["max_hp"], s["hp"] + healed)
        text = f"{s['name']} drinks a potion and heals {healed}."
    if raid["hp"] <= 0:
        finish_raid(db, party_id, raid, key)
    elif mode != "potion" or random.random() < 0.65:
        text += " " + raid_counterattack(s, raid)
    damage += max(0, dealt)
    healing += max(0, healed)
    db.execute("INSERT INTO raid_actions(party_id,player_key,skill_used,damage,healing) VALUES(?,?,?,?,?) ON CONFLICT(party_id,player_key) DO UPDATE SET skill_used=excluded.skill_used,damage=excluded.damage,healing=excluded.healing", (party_id, key, int(skill_used), damage, healing))
    raid_event(db, party_id, key, text)
    save_raid(db, party_id, raid)
    db.commit()
    return text


def claim_raid_reward(db: sqlite3.Connection, key: str, s: Dict) -> None:
    row = db.execute("SELECT party_id,xp,gold FROM raid_rewards WHERE player_key=? AND claimed=0 ORDER BY rowid LIMIT 1", (key,)).fetchone()
    if not row: return
    s["xp"] += row["xp"]
    s["gold"] += row["gold"]
    s["score"] += row["xp"] + row["gold"]
    db.execute("UPDATE raid_rewards SET claimed=1 WHERE party_id=? AND player_key=?", (row["party_id"], key))
    add_log(s, f"PARTY RAID REWARD: +{row['xp']} XP and +{row['gold']} gold.")
    maybe_level(s)
    db.commit()


def board_post(db: sqlite3.Connection, key: str, s: Dict, text: str) -> str:
    msg = safe_message(text)
    if not msg: return "Your message was empty."
    recent = db.execute("SELECT created_at FROM board WHERE player_key=? ORDER BY id DESC LIMIT 1", (key,)).fetchone()
    if recent and now_ts() - recent["created_at"] < 8: return "The barkeep asks you not to shout so quickly."
    db.execute("INSERT INTO board(player_key,name,message,created_at) VALUES(?,?,?,?)", (key, s["name"], msg, now_ts()))
    db.execute("DELETE FROM board WHERE id NOT IN (SELECT id FROM board ORDER BY id DESC LIMIT 60)")
    db.commit()
    return "Your message is pinned to the tavern board."


def duel_name(db: sqlite3.Connection, key: str) -> str:
    row = db.execute("SELECT name FROM scores WHERE player_key=?", (key,)).fetchone()
    return row["name"] if row else key[:8]


def create_duel(db: sqlite3.Connection, challenger: str, target: str) -> str:
    if challenger == target: return "You cannot challenge yourself."
    if not db.execute("SELECT 1 FROM players WHERE player_key=?", (target,)).fetchone(): return "That LXMF player is not registered here."
    existing = db.execute("SELECT 1 FROM duels WHERE status IN ('pending','active') AND ((challenger=? AND target=?) OR (challenger=? AND target=?))", (challenger, target, target, challenger)).fetchone()
    if existing: return "A duel between you already exists."
    db.execute("INSERT INTO duels(challenger,target,status,created_at,updated_at) VALUES(?,?, 'pending',?,?)", (challenger, target, now_ts(), now_ts()))
    db.commit()
    return f"Challenge sent to {duel_name(db, target)}."


def accept_duel(db: sqlite3.Connection, duel_id: int, key: str) -> str:
    d = db.execute("SELECT * FROM duels WHERE id=? AND target=? AND status='pending'", (duel_id, key)).fetchone()
    if not d: return "That challenge is no longer available."
    a = load_state(db, d["challenger"])
    b = load_state(db, d["target"])
    if not a or not b: return "One duelist no longer exists."
    turn = random.choice([d["challenger"], d["target"]])
    log = f"The duel begins. {duel_name(db, turn)} has initiative."
    db.execute("UPDATE duels SET status='active',turn=?,hp_challenger=?,hp_target=?,log=?,updated_at=? WHERE id=?", (turn, a["max_hp"], b["max_hp"], log, now_ts(), duel_id))
    db.commit()
    return log


def decline_duel(db: sqlite3.Connection, duel_id: int, key: str) -> str:
    cur = db.execute("UPDATE duels SET status='declined',updated_at=? WHERE id=? AND target=? AND status='pending'", (now_ts(), duel_id, key))
    db.commit()
    return "Challenge declined." if cur.rowcount else "That challenge is no longer available."


def duel_attack(db: sqlite3.Connection, duel_id: int, key: str, s: Dict, power: bool = False) -> str:
    db.execute("BEGIN IMMEDIATE")
    d = db.execute("SELECT * FROM duels WHERE id=? AND status='active'", (duel_id,)).fetchone()
    if not d or key not in (d["challenger"], d["target"]):
        db.rollback(); return "That duel is not active."
    if d["turn"] != key:
        db.rollback(); return "It is not your turn."
    foe_key = d["target"] if key == d["challenger"] else d["challenger"]
    foe = load_state(db, foe_key)
    if not foe:
        db.rollback(); return "Your opponent is gone."
    roll = random.randint(1, 20)
    total = roll + attack_bonus(s) - (2 if power else 0)
    hit = roll == 20 or (roll != 1 and total >= armor_class(foe))
    dmg = 0
    if hit:
        dmg = damage_roll(s) + (4 if power else 0)
        if roll == 20: dmg += damage_roll(s)
    hp_c = d["hp_challenger"]
    hp_t = d["hp_target"]
    if foe_key == d["challenger"]: hp_c -= dmg
    else: hp_t -= dmg
    if hit: text = f"{s['name']} {'CRITS' if roll == 20 else 'hits'} {foe['name']} for {dmg}."
    else: text = f"{s['name']} attacks {foe['name']} and misses."
    if hp_c <= 0 or hp_t <= 0:
        text += f" {s['name']} wins the duel!"
        s["duel_wins"] = s.get("duel_wins", 0) + 1
        s["score"] += 25
        db.execute("UPDATE duels SET status='complete',turn=NULL,hp_challenger=?,hp_target=?,log=?,updated_at=? WHERE id=?", (max(0,hp_c), max(0,hp_t), text, now_ts(), duel_id))
    else:
        db.execute("UPDATE duels SET turn=?,hp_challenger=?,hp_target=?,log=?,updated_at=? WHERE id=?", (foe_key, hp_c, hp_t, text, now_ts(), duel_id))
    db.commit()
    return text


def duel_forfeit(db: sqlite3.Connection, duel_id: int, key: str) -> str:
    d = db.execute("SELECT * FROM duels WHERE id=? AND status='active' AND (challenger=? OR target=?)", (duel_id, key, key)).fetchone()
    if not d: return "That duel is not active."
    winner = d["target"] if key == d["challenger"] else d["challenger"]
    db.execute("UPDATE duels SET status='complete',turn=NULL,log=?,updated_at=? WHERE id=?", (f"{duel_name(db,key)} forfeits. {duel_name(db,winner)} wins.", now_ts(), duel_id))
    db.commit()
    return "You forfeit the duel."


def link(label: str, fields: Tuple[str, ...] = (), **vars_: str) -> str:
    parts = list(fields) + [f"{k}={v}" for k, v in vars_.items()]
    payload = "|".join(parts)
    return f"[{label}`{PAGE_PATH}`{payload}]" if payload else f"[{label}`{PAGE_PATH}]"


def literal(art: str) -> List[str]:
    return ["`="] + art.strip("\n").splitlines() + ["`=", ""]


def bar(value: int, maximum: int, width: int = 18) -> str:
    maximum = max(1, maximum)
    fill = clamp(round(width * value / maximum), 0, width)
    return "[" + "#" * fill + "." * (width - fill) + "]"


def age_text(ts: int | None) -> str:
    if not ts: return "offline"
    d = max(0, now_ts() - int(ts))
    if d < 60: return "now"
    if d < 3600: return f"{d//60}m"
    if d < 86400: return f"{d//3600}h"
    return f"{d//86400}d"


def gear_name(item: Dict | None) -> str:
    if not item: return "None"
    parts = []
    if item.get("attack"): parts.append(f"ATK +{item['attack']}")
    if item.get("damage"): parts.append(f"DMG +{item['damage']}")
    if item.get("ac"): parts.append(f"AC +{item['ac']}")
    return f"{item['name']} ({', '.join(parts)})" if parts else item["name"]


def render_header(db: sqlite3.Connection, s: Dict) -> List[str]:
    online = db.execute("SELECT COUNT(*) FROM players WHERE updated_at>=?", (now_ts() - ONLINE_WINDOW,)).fetchone()[0]
    total = db.execute("SELECT COUNT(*) FROM players").fetchone()[0]
    lines = ["#!c=0"] + literal(ASCII["title"])
    lines += [f">{GAME_TITLE}", f"*{s['name']}* — Level {s['level']} {CLASSES[s['class']]['name']}", f"LXMF: `{s['address']}`", f"Players: {total} registered | {online} active in the last 15m", "-"]
    lines += [f"HP {bar(s['hp'], s['max_hp'])} {s['hp']}/{s['max_hp']} | AC {armor_class(s)} | Attack +{attack_bonus(s)}", f"XP {s['xp']}/{xp_needed(s['level'])} | Gold {s['gold']} | Potions {s['potions']} | Score {s['score']}", ""]
    return lines


def render_nav() -> List[str]:
    return [link("Dungeon", action="view"), " | ", link("Tavern", action="tavern"), " | ", link("Players", action="players"), " | ", link("Party", action="party"), " | ", link("Arena", action="arena"), " | ", link("Legends", action="scores"), "", "-"]


def render_log(s: Dict) -> List[str]:
    lines = [">>Chronicle"]
    lines.extend(f"• {m}" for m in s.get("log", [])[:MAX_LOG])
    return lines + [""]


def render_character(s: Dict) -> List[str]:
    c = CLASSES[s["class"]]
    return [">>Character", f"LXMF player: `{s['address']}`", f"Class ability: *{c['skill']}* — {c['desc']}", f"Weapon: {gear_name(s.get('weapon'))}", f"Armor: {gear_name(s.get('armor'))}", f"Deepest dungeon: {s['deepest']} | Bosses: {s['victories']} | Deaths: {s['deaths']} | Duel wins: {s.get('duel_wins',0)}", "", link("Return", action="view"), ""]


def render_crossroads(s: Dict) -> List[str]:
    lines = literal(ASCII["gate"])
    lines += [">>Choose your path", "The keep rearranges itself after every expedition." if s["rooms"] == 0 else "Three passages lead onward.", "", link("Torch-lit hall", action="explore", route="torch"), " — balanced", link("Iron stairs", action="explore", route="stairs"), " — dangerous, combat-heavy", link("Whispering runes", action="explore", route="whisper"), " — strange rooms and riddles", ""]
    if s["rooms"] == 0: lines.append(link("Rest at the gate - 5 gold", action="rest"))
    else: lines.append(link("Return safely to the gate", action="abandon"))
    lines += ["", link("Character sheet", action="character"), ""]
    return lines


def render_combat(s: Dict) -> List[str]:
    e = s["enemy"]
    lines = literal(ASCII.get(e.get("art"), ASCII["guard"]))
    lines += [f">>Combat: {e['name']}", f"Enemy HP {bar(max(0,e['hp']), e['max_hp'])} {max(0,e['hp'])}/{e['max_hp']} | AC {e['ac']}"]
    if e.get("boss"): lines.append("*BOSS:* the chamber is sealed.")
    if e.get("weakened", 0): lines.append("Enemy weakened: -2 attack.")
    lines += ["", link("Attack", action="attack"), link("Power attack", action="power"), link("Guard", action="guard"), link(CLASSES[s["class"]]["skill"], action="skill"), link("Drink potion", action="potion"), link("Flee", action="flee"), ""]
    return lines


def render_treasure(s: Dict) -> List[str]:
    item = s.get("pending_loot")
    if not item: return render_crossroads(s)
    lines = literal(ASCII["chest"])
    lines += [">>Treasure", f"You found *{gear_name(item)}*.", ""]
    current = s.get(item["slot"])
    if current: lines.append(f"Current {item['slot']}: {gear_name(current)}")
    lines += [link("Equip it", action="equip"), link(f"Sell it for {item['value']} gold", action="sell"), ""]
    return lines


def render_merchant(s: Dict) -> List[str]:
    lines = literal(ASCII["merchant"])
    return lines + [">>The Red-Suitcase Peddler", "'No refunds. No curses removed.'", "", link(f"Healing draught - {10+s['level']*2}g", action="buy", item="potion"), link(f"Full restorative - {8+s['level']}g", action="buy", item="heal"), link(f"Sealed equipment - {28+s['level']*3}g", action="buy", item="mystery"), link("Leave", action="leave_shop"), ""]


def render_puzzle(s: Dict) -> List[str]:
    p = s.get("puzzle")
    if not p: return render_crossroads(s)
    lines = literal(ASCII["runes"])
    return lines + [">>Runed Door", p["question"], "", "Answer: <24|answer`>", link("Speak answer", fields=("answer",), action="puzzle"), "", "Wrong answers trigger the ward.", ""]


def render_tavern(db: sqlite3.Connection, key: str, s: Dict, notice: str = "") -> List[str]:
    lines = literal(ASCII["tavern"])
    lines += [">>The Ash & Lantern Tavern", "This board is shared by every registered LXMF player on this node.", ""]
    if notice: lines += [f"*{notice}*", ""]
    rows = db.execute("SELECT player_key,name,message,created_at FROM board ORDER BY id DESC LIMIT 12").fetchall()
    if rows:
        for r in rows:
            lines.append(f"{r['name']} <{r['player_key'][:8]}> [{age_text(r['created_at'])}]: {r['message']}")
    else: lines.append("The message board is empty.")
    lines += ["", "Message: <72|message`>", link("Post to tavern board", fields=("message",), action="board_post"), "", link("Browse players", action="players"), " | ", link("Party hall", action="party"), ""]
    return lines


def render_players(db: sqlite3.Connection, key: str) -> List[str]:
    lines = [">>LXMF Player Roster", "Each 32-hex LXMF address is the permanent player identifier.", ""]
    rows = db.execute("SELECT s.player_key,s.name,s.level,s.deepest,s.score,p.updated_at FROM scores s LEFT JOIN players p ON p.player_key=s.player_key ORDER BY p.updated_at DESC,s.score DESC LIMIT 40").fetchall()
    for r in rows:
        online = "ONLINE" if r["updated_at"] and r["updated_at"] >= now_ts()-ONLINE_WINDOW else age_text(r["updated_at"])
        marker = "YOU" if r["player_key"] == key else online
        lines += [f"*{r['name']}* L{r['level']} | depth {r['deepest']} | score {r['score']} | {marker}", f"`{r['player_key']}`"]
        if r["player_key"] != key:
            lines += [link("Challenge to duel", action="duel_challenge", target=r["player_key"]), ""]
        else: lines.append("")
    if not rows: lines.append("No players registered yet.")
    return lines


def render_party(db: sqlite3.Connection, key: str, s: Dict, notice: str = "") -> List[str]:
    lines = literal(ASCII["party"])
    lines += [">>Party Hall"]
    if notice: lines += [f"*{notice}*", ""]
    party = party_for(db, key)
    if not party:
        lines += ["You are not in a party.", "", "Party name: <24|party_name`Ashbound Company>", link("Create open party", fields=("party_name",), action="party_create"), "", ">>>Open parties"]
        rows = db.execute("SELECT p.party_id,p.name,p.leader,COUNT(m.player_key) AS members FROM parties p LEFT JOIN party_members m ON p.party_id=m.party_id GROUP BY p.party_id ORDER BY p.created_at DESC LIMIT 15").fetchall()
        for r in rows:
            if r["members"] < MAX_PARTY:
                lines += [f"{r['name']} — {r['members']}/{MAX_PARTY} — leader {duel_name(db,r['leader'])}", link("Join", action="party_join", party=r["party_id"]), ""]
        if not rows: lines.append("No open parties yet.")
        return lines
    members = party_members(db, party["party_id"])
    lines += [f"*{party['name']}* — party code `{party['party_id']}` — {len(members)}/{MAX_PARTY}", ""]
    for m in members:
        status = "online" if m["updated_at"] and m["updated_at"] >= now_ts()-ONLINE_WINDOW else age_text(m["updated_at"])
        leader = " [LEADER]" if m["player_key"] == party["leader"] else ""
        lines += [f"{m['name'] or m['player_key'][:8]} L{m['level'] or 1} — {status}{leader}", f"`{m['player_key']}`"]
    lines += ["", link("Leave party", action="party_leave"), "", ">>>Shared Raid"]
    raid = load_raid(db, party["party_id"])
    if not raid or raid.get("status") == "defeated":
        if raid and raid.get("status") == "defeated": lines.append(f"Last raid victory: {raid['name']} was defeated.")
        lines += [link("Begin a new party raid", action="raid_start"), ""]
    else:
        lines += literal(ASCII.get(raid.get("art"), ASCII["ogre"]))
        lines += [f"*{raid['name']}*", f"Shared HP {bar(max(0,raid['hp']),raid['max_hp'])} {max(0,raid['hp'])}/{raid['max_hp']} | AC {raid['ac']}", f"Your HP {bar(s['hp'],s['max_hp'])} {s['hp']}/{s['max_hp']}", "", link("Raid attack", action="raid_attack"), link("Class raid ability", action="raid_skill"), link("Drink potion", action="raid_potion"), "", ">>>Raid battle log"]
        events = db.execute("SELECT text FROM raid_events WHERE party_id=? ORDER BY id DESC LIMIT 10", (party["party_id"],)).fetchall()
        lines.extend(f"• {e['text']}" for e in events)
        stats = db.execute("SELECT a.player_key,a.damage,a.healing,s.name FROM raid_actions a LEFT JOIN scores s ON s.player_key=a.player_key WHERE a.party_id=? ORDER BY a.damage DESC", (party["party_id"],)).fetchall()
        if stats:
            lines += ["", ">>>Contributions"]
            lines.extend(f"{r['name'] or r['player_key'][:8]} — damage {r['damage']} | healing {r['healing']}" for r in stats)
    return lines + [""]


def active_duel_for(db: sqlite3.Connection, key: str) -> sqlite3.Row | None:
    return db.execute("SELECT * FROM duels WHERE status='active' AND (challenger=? OR target=?) ORDER BY id DESC LIMIT 1", (key,key)).fetchone()


def render_arena(db: sqlite3.Connection, key: str, s: Dict, notice: str = "") -> List[str]:
    lines = literal(ASCII["arena"])
    lines += [">>LXMF Arena", "Duels require the other player to accept. Duel HP is separate from dungeon HP.", ""]
    if notice: lines += [f"*{notice}*", ""]
    active = active_duel_for(db, key)
    if active:
        foe_key = active["target"] if key == active["challenger"] else active["challenger"]
        my_hp = active["hp_challenger"] if key == active["challenger"] else active["hp_target"]
        foe_hp = active["hp_target"] if key == active["challenger"] else active["hp_challenger"]
        me_max = load_state(db,key)["max_hp"] if load_state(db,key) else max(1,my_hp)
        foe_state = load_state(db,foe_key)
        foe_max = foe_state["max_hp"] if foe_state else max(1,foe_hp)
        lines += [f"You vs *{duel_name(db,foe_key)}*", f"Your duel HP {bar(my_hp,me_max)} {my_hp}/{me_max}", f"Opponent HP {bar(foe_hp,foe_max)} {foe_hp}/{foe_max}", f"Last action: {active['log']}", ""]
        if active["turn"] == key:
            lines += ["*YOUR TURN*", link("Attack", action="duel_attack", duel=str(active["id"])), link("Power attack", action="duel_power", duel=str(active["id"])), link("Forfeit", action="duel_forfeit", duel=str(active["id"])), ""]
        else: lines += [f"Waiting for {duel_name(db,foe_key)} to act.", link("Refresh arena", action="arena"), ""]
    pending = db.execute("SELECT * FROM duels WHERE target=? AND status='pending' ORDER BY id DESC LIMIT 10", (key,)).fetchall()
    if pending:
        lines += [">>>Incoming challenges"]
        for d in pending:
            lines += [f"{duel_name(db,d['challenger'])} <{d['challenger'][:8]}> challenges you.", link("Accept", action="duel_accept", duel=str(d["id"])), " | ", link("Decline", action="duel_decline", duel=str(d["id"])), ""]
    recent = db.execute("SELECT * FROM duels WHERE status='complete' AND (challenger=? OR target=?) ORDER BY updated_at DESC LIMIT 5", (key,key)).fetchall()
    if recent:
        lines += [">>>Recent duels"] + [f"• {d['log']}" for d in recent] + [""]
    lines += [link("Find opponents in player roster", action="players"), ""]
    return lines


def render_scores(db: sqlite3.Connection) -> List[str]:
    rows = db.execute("SELECT player_key,name,level,deepest,victories,score FROM scores ORDER BY score DESC,deepest DESC LIMIT 15").fetchall()
    lines = [">>Hall of Legends"]
    for i,r in enumerate(rows,1):
        lines += [f"{i}. {r['name']} — L{r['level']} | depth {r['deepest']} | bosses {r['victories']} | score {r['score']}", f"   `{r['player_key']}`"]
    if not rows: lines.append("No legends yet.")
    return lines + [""]


def render_footer() -> List[str]:
    return ["-", link("Refresh", action="view"), " | ", link("Reset character", action="confirm_reset"), "", "_Original fantasy game. LXMF address = player identity._"]


def render_create(address: str) -> str:
    lines = ["#!c=0"] + literal(ASCII["title"])
    lines += [f">{GAME_TITLE}", "*Your identified LXMF address is your player account.*", f"LXMF: `{address}`", "", "Adventurer name: <20|name`Traveler>", "", ">>Choose a class"]
    for key,c in CLASSES.items():
        lines += [f"*{c['name']}* — {c['desc']}", f"[Create {c['name']}`{PAGE_PATH}`name|action=create|class={key}]", ""]
    return "\n".join(lines)


def render_identify_required() -> str:
    lines = ["#!c=0"] + literal(ASCII["title"])
    lines += [f">{GAME_TITLE}", "*Identification required.*", "", "This multiplayer world does not create guest players.", "Your NomadNet connection must identify to the node so the game can derive your unique `lxmf.delivery` address.", "", "Enable *Identify When Connecting* for this node, reconnect, then load the game again.", "", "Every identified LXMF address becomes one persistent multiplayer player."]
    return "\n".join(lines)


def render_reset_confirm() -> List[str]:
    return [">>Reset character?", "This erases the character tied to your LXMF address and removes it from the score table.", "", link("YES - erase", action="reset"), link("No - return", action="view"), ""]


def process_action(db: sqlite3.Connection, key: str, identity: str, s: Dict, action: str) -> str:
    notice = ""
    if action == "explore" and s.get("room_type") == "crossroads" and not s.get("enemy"):
        enter_room(s, get_var("route", "torch")); handle_death(s)
    elif action == "attack": do_attack(s)
    elif action == "power": do_attack(s, True)
    elif action == "guard": do_guard(s)
    elif action == "skill": do_skill(s)
    elif action == "potion": do_potion(s)
    elif action == "flee": do_flee(s)
    elif action == "equip": equip_pending(s)
    elif action == "sell": sell_pending(s)
    elif action == "buy": merchant_buy(s, get_var("item", ""))
    elif action == "leave_shop" and s.get("room_type") == "merchant":
        s["room_type"] = "crossroads"; add_log(s, "The peddler vanishes down an impossible corridor.")
    elif action == "puzzle": solve_puzzle(s, get_field("answer", ""))
    elif action == "rest": rest_at_gate(s)
    elif action == "abandon": abandon_run(s)
    elif action == "board_post": notice = board_post(db, key, s, get_field("message", ""))
    elif action == "party_create":
        pid = make_party(db, key, get_field("party_name", "DarkTide Company")); notice = f"Party created. Code {pid}."
    elif action == "party_join": notice = join_party(db, key, get_var("party", ""))
    elif action == "party_leave": notice = leave_party(db, key)
    elif action == "raid_start":
        p = party_for(db,key)
        if p: raid = start_raid(db,p["party_id"]); notice = f"{raid['name']} has appeared!"
        else: notice = "Join a party first."
    elif action in ("raid_attack","raid_skill","raid_potion"):
        notice = raid_action(db,key,s,action.replace("raid_",""))
    elif action == "duel_challenge": notice = create_duel(db,key,get_var("target",""))
    elif action == "duel_accept": notice = accept_duel(db,int(get_var("duel","0") or 0),key)
    elif action == "duel_decline": notice = decline_duel(db,int(get_var("duel","0") or 0),key)
    elif action == "duel_attack": notice = duel_attack(db,int(get_var("duel","0") or 0),key,s,False)
    elif action == "duel_power": notice = duel_attack(db,int(get_var("duel","0") or 0),key,s,True)
    elif action == "duel_forfeit": notice = duel_forfeit(db,int(get_var("duel","0") or 0),key)
    claim_raid_reward(db,key,s)
    record_activity(db,key,action,notice)
    save_state(db,key,identity,s)
    return notice


def main() -> None:
    key, identity = player_identity()
    if not key or not identity:
        print(render_identify_required())
        return
    db = init_db()
    action = get_var("action", "view")
    s = load_state(db,key)
    if action == "reset":
        record_activity(db,key,"reset","Character reset")
        db.commit()
        reset_character(db,key)
        print(render_create(key))
        return
    if s is None:
        if action == "create":
            cls = get_var("class", "fighter").lower()
            if cls not in CLASSES: cls = "fighter"
            s = new_state(get_field("name", "Traveler"), cls, key)
            save_state(db,key,identity,s)
        else:
            print(render_create(key))
            return
    notice = process_action(db,key,identity,s,action)
    lines = render_header(db,s) + render_nav()
    if action == "scores": lines += render_scores(db)
    elif action == "character": lines += render_character(s)
    elif action == "confirm_reset": lines += render_reset_confirm()
    elif action in ("tavern","board_post"): lines += render_tavern(db,key,s,notice)
    elif action == "players" or action == "duel_challenge":
        if notice: lines += [f"*{notice}*", ""]
        lines += render_players(db,key)
    elif action.startswith("party_") or action.startswith("raid_") or action == "party": lines += render_party(db,key,s,notice)
    elif action.startswith("duel_") or action == "arena": lines += render_arena(db,key,s,notice)
    else:
        lines += render_log(s)
        if s.get("enemy"): lines += render_combat(s)
        elif s.get("room_type") == "treasure" and s.get("pending_loot"): lines += render_treasure(s)
        elif s.get("room_type") == "merchant": lines += render_merchant(s)
        elif s.get("room_type") == "puzzle" and s.get("puzzle"): lines += render_puzzle(s)
        else: lines += render_crossroads(s)
    lines += render_footer()
    print("\n".join(lines))


if __name__ == "__main__":
    main()
