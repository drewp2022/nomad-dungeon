#!/usr/bin/env python3

import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "index.mu"
DASHBOARD = ROOT / "dashboard.py"
BACKUP = ROOT / "backup.py"
ID1 = "00112233445566778899aabbccddeeff"
ID2 = "ffeeddccbbaa99887766554433221100"


def lxmf(identity_hex):
    name_hash = hashlib.sha256(b"lxmf.delivery").digest()[:10]
    return hashlib.sha256(name_hash + bytes.fromhex(identity_hex)).digest()[:16].hex()


def run(page, identity=None, **values):
    env = os.environ.copy()
    if identity:
        env["DARKTSUNAMI_TEST_IDENTITY"] = identity
    env.update({k: str(v) for k, v in values.items()})
    return subprocess.check_output([str(page)], env=env, text=True)


def main():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        page = root / "index.mu"
        shutil.copy2(SOURCE, page)
        page.chmod(0o755)

        out = run(page)
        assert "Identification required" in out
        assert "DARKTSUNAMI KEEP" in out
        assert "DarkTsunami Keep: LXMF Realms" in out

        a1 = lxmf(ID1)
        a2 = lxmf(ID2)
        assert a1 == "82de33c3aa80110d9e5af20b6b7eda4f"
        assert a2 == "6a5f01cae47a15989c032ab93c3b3f06"

        out = run(page, ID1, field_name="Drew", var_action="create", var_class="mage")
        assert a1 in out and "Drew" in out
        out = run(page, ID2, field_name="Aria", var_action="create", var_class="cleric")
        assert a2 in out and "Aria" in out

        dbp = root / ".darktsunami_keep" / "game.sqlite3"
        db = sqlite3.connect(dbp)
        db.row_factory = sqlite3.Row
        keys = {r[0] for r in db.execute("SELECT player_key FROM players")}
        assert keys == {a1, a2}
        assert db.execute("SELECT value FROM meta WHERE key='game_title'").fetchone()[0] == "DarkTsunami Keep: LXMF Realms"
        assert db.execute("SELECT COUNT(*) FROM activity WHERE action='create'").fetchone()[0] == 2

        out = run(page, ID1, var_action="players")
        assert a1 in out and a2 in out and "Challenge to duel" in out

        out = run(page, ID1, field_message="Meet at the gate!", var_action="board_post")
        assert "Meet at the gate!" in out

        run(page, ID1, field_party_name="Tsunami Knights", var_action="party_create")
        party_id = db.execute("SELECT party_id FROM parties WHERE leader=?", (a1,)).fetchone()[0]
        out = run(page, ID2, var_action="party_join", var_party=party_id)
        assert "You joined Tsunami Knights" in out
        assert db.execute("SELECT COUNT(*) FROM party_members WHERE party_id=?", (party_id,)).fetchone()[0] == 2

        run(page, ID1, var_action="raid_start")
        before = json.loads(db.execute("SELECT state_json FROM raid_state WHERE party_id=?", (party_id,)).fetchone()[0])["hp"]
        run(page, ID1, var_action="raid_skill")
        after = json.loads(db.execute("SELECT state_json FROM raid_state WHERE party_id=?", (party_id,)).fetchone()[0])["hp"]
        assert after < before
        out = run(page, ID2, var_action="party")
        assert str(after) in out or "Shared HP" in out

        run(page, ID1, var_action="duel_challenge", var_target=a2)
        duel_id = db.execute("SELECT id FROM duels WHERE challenger=? AND target=? ORDER BY id DESC LIMIT 1", (a1, a2)).fetchone()[0]
        run(page, ID2, var_action="duel_accept", var_duel=duel_id)
        d = db.execute("SELECT status,turn FROM duels WHERE id=?", (duel_id,)).fetchone()
        assert d["status"] == "active" and d["turn"] in (a1, a2)

        for _ in range(100):
            d = db.execute("SELECT status,turn FROM duels WHERE id=?", (duel_id,)).fetchone()
            if d["status"] != "active":
                break
            ident = ID1 if d["turn"] == a1 else ID2
            run(page, ident, var_action="duel_power", var_duel=duel_id)
        assert db.execute("SELECT status FROM duels WHERE id=?", (duel_id,)).fetchone()[0] == "complete"
        assert db.execute("SELECT COUNT(*) FROM activity").fetchone()[0] >= 8
        db.close()

        check = subprocess.run([str(DASHBOARD), "--check", "--db", str(dbp)], text=True, capture_output=True)
        assert check.returncode == 0, check.stdout + check.stderr
        snap = json.loads(check.stdout)
        assert snap["database"]["ok"] is True
        assert snap["database"]["counts"]["players"] == 2
        assert snap["database"]["counts"]["parties"] == 1
        assert snap["database"]["meta"]["game_version"] == "1.0.0"

        backup_dir = root / "backups"
        backup = subprocess.run([str(BACKUP), "--db", str(dbp), "--output", str(backup_dir), "--keep", "2"], text=True, capture_output=True)
        assert backup.returncode == 0, backup.stdout + backup.stderr
        copies = list(backup_dir.glob("darktsunami-keep-*.sqlite3"))
        assert len(copies) == 1
        bdb = sqlite3.connect(copies[0])
        assert bdb.execute("PRAGMA quick_check").fetchone()[0] == "ok"
        assert bdb.execute("SELECT COUNT(*) FROM players").fetchone()[0] == 2
        bdb.close()

        for filename in ("index.mu", "backup.py", "test_game.py"):
            source = (ROOT / filename).read_text()
            comments = [line for line in source.splitlines() if line.lstrip().startswith("#")]
            assert comments == ["#!/usr/bin/env python3"]

        dashboard_source = DASHBOARD.read_text()
        dashboard_comments = [line for line in dashboard_source.splitlines() if line.lstrip().startswith("#")]
        assert len(dashboard_comments) >= 20
        assert "BURN GUARD" not in dashboard_source
        assert "◆" not in dashboard_source
        assert "def burn_shift" in dashboard_source
        assert "place_configure" in dashboard_source

    print("DarkTsunami Keep production multiplayer tests: PASS")


if __name__ == "__main__":
    main()
