#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sqlite3
from datetime import datetime
from pathlib import Path

DEFAULT_DB = Path.home() / ".nomadnetwork" / "storage" / "pages" / ".darktsunami_keep" / "game.sqlite3"
DEFAULT_BACKUPS = Path.home() / ".local" / "share" / "darktsunami-keep" / "backups"


def backup_database(source: Path, target_dir: Path, keep: int) -> Path:
    if not source.exists():
        raise FileNotFoundError(source)
    target_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    target = target_dir / f"darktsunami-keep-{stamp}.sqlite3"
    src = sqlite3.connect(f"file:{source}?mode=ro", uri=True, timeout=10.0)
    dst = sqlite3.connect(target, timeout=10.0)
    try:
        src.backup(dst)
        result = dst.execute("PRAGMA quick_check").fetchone()[0]
        if result != "ok":
            raise RuntimeError(f"backup integrity check failed: {result}")
    finally:
        dst.close()
        src.close()
    backups = sorted(target_dir.glob("darktsunami-keep-*.sqlite3"), key=lambda p: p.stat().st_mtime, reverse=True)
    for old in backups[max(1, keep):]:
        old.unlink(missing_ok=True)
    return target


def main() -> int:
    parser = argparse.ArgumentParser(prog="darktsunami-backup")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--output", type=Path, default=DEFAULT_BACKUPS)
    parser.add_argument("--keep", type=int, default=14)
    args = parser.parse_args()
    try:
        target = backup_database(args.db.expanduser().resolve(), args.output.expanduser().resolve(), max(1, args.keep))
        print(target)
        return 0
    except Exception as exc:
        print(f"Backup failed: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
