DarkTsunami Keep: LXMF Realms
DarkTsunami Keep is a persistent multiplayer fantasy dungeon game for NomadNet. The game runs as an executable Python Micron page and uses each identified player's 32-hex LXMF `lxmf.delivery` address as the permanent player ID.
The production package also includes a local graphical server dashboard for the machine running NomadNet.
Production features
LXMF address based persistent player accounts
No guest or link-ID player records
Shared multiplayer roster
Persistent tavern board
Four-player parties
Shared asynchronous raid bosses
Consent-based asynchronous PvP duels
Hall of Legends
ASCII title, dungeon, monster, boss, tavern, party and arena graphics
SQLite WAL database
Database indices for multiplayer queries
Activity/audit event history
Automatic migration from the previous `.ashfall\_keep` database
Local read-only graphical dashboard
Host CPU, load, memory, disk and uptime monitoring
Complete player state inspection
Party, raid, duel, tavern and activity views
Database size, WAL size, schema and integrity status
Consistent SQLite backup utility
Optional daily systemd user backup timer
Desktop launcher and GUI autostart
Minimal Python comments: Python files contain only their required shebang comment line
Files
```text
darktsunami\_keep\_nomadnet/
├── index.mu
├── dashboard.py
├── backup.py
├── test\_game.py
├── install.sh
├── uninstall.sh
├── darktsunami-keep-backup.service
├── darktsunami-keep-backup.timer
└── README.md
```
Install
```bash
unzip darktsunami\_keep\_nomadnet.zip
cd darktsunami\_keep\_nomadnet
./install.sh
```
The installer places the NomadNet page at:
```text
\~/.nomadnetwork/storage/pages/index.mu
```
Game data is stored at:
```text
\~/.nomadnetwork/storage/pages/.darktsunami\_keep/game.sqlite3
```
The local dashboard is installed at:
```text
\~/.local/bin/darktsunami-dashboard
```
The backup utility is installed at:
```text
\~/.local/bin/darktsunami-backup
```
A desktop launcher is added and the dashboard is configured to start automatically at graphical login.
Use these installer options when needed:
```bash
./install.sh --no-autostart
./install.sh --no-backup-timer
./install.sh --launch
```
Options may be combined.
Existing Ashfall Keep saves
If this file exists:
```text
\~/.nomadnetwork/storage/pages/.ashfall\_keep/game.sqlite3
```
and a DarkTsunami Keep database does not already exist, the installer performs a consistent SQLite backup migration into:
```text
\~/.nomadnetwork/storage/pages/.darktsunami\_keep/game.sqlite3
```
The game page also contains one-time migration logic in case the page is installed manually.
The old database is not deleted.
Start the game
Open this page in NomadNet:
```text
:/page/index.mu
```
Players must enable Identify When Connecting for the node. A visitor without an authenticated identity receives the identification-required screen and no guest player is created.
LXMF player identity
NomadNet exposes the authenticated Reticulum identity hash to the executable page as `remote\_identity`.
DarkTsunami Keep derives the corresponding LXMF destination address using the `lxmf.delivery` destination hash. The resulting 32-hex LXMF address is used directly as the database player key.
Character names are display names only.
Dashboard
Launch manually with:
```bash
darktsunami-dashboard
```
Or from the desktop application menu as DarkTsunami Keep Dashboard.
The dashboard refreshes every two seconds and is read-only against the live game database.
Always-visible burn-in protection
The dashboard never blanks, turns black or hides the server statistics. Burn-in protection is handled by moving visible content instead:
the entire visible stats panel follows a 28-pixel-wide by 16-pixel-high drift path
the panel changes position every 3 seconds while the dashboard is running
burn-in protection runs silently with no burn-guard label, indicator, or X/Y offset shown on screen
after 5 minutes without mouse or keyboard input, the visible statistics tab advances every 2 minutes
mouse or keyboard activity immediately suspends automatic tab cycling
live database refresh continues normally during protection
no dimming, black overlay or screensaver is used
The movement remains visible, but the protection itself is not labeled on screen. The stats remain readable and on-screen at all times.
Overview
Shows:
registered players
players active within 15 minutes
parties
active raids
pending and active duels
highest level
deepest dungeon depth
total score
total gold
boss kills
deaths
leaderboard
host name
operating system
architecture
Python version
CPU utilization
1, 5 and 15 minute load averages
memory usage
disk usage
system uptime
database size
WAL and SHM sizes
database integrity result
game and schema versions
activity, raid event and tavern post totals
Players
Shows every registered LXMF player with:
character name
full LXMF address
class
level
current/max HP
XP
gold
potions
rooms
deepest level
boss victories
deaths
duel wins
score
current room
current enemy
weapon
armor
creation time
last activity
complete raw persistent character state
Parties & Raids
Shows:
party name and ID
leader
member list
join times
current raid boss
raid HP
raid state
member damage
member healing
class ability usage
recent raid events
Duels
Shows:
duel ID
challenger
target
status
current turn
both duel HP values
last action
creation and update times
Tavern
Shows the shared tavern message history with player name, LXMF address and timestamp.
Activity
Shows recent meaningful game actions recorded by the production build.
Database
Shows database status, path, integrity state, game metadata, aggregate counts and SQLite file sizes.
Integrity checking is performed periodically instead of on every two-second GUI refresh to avoid unnecessary load on the live database.
Dashboard dependency
The game itself uses only Python's standard library.
The GUI uses Python Tkinter. On systems where Tkinter is packaged separately, install the distribution's Python Tk package before running the dashboard. The installer prints a warning if Tkinter is unavailable.
Backups
Create a verified backup manually:
```bash
darktsunami-backup
```
Backups are written to:
```text
\~/.local/share/darktsunami-keep/backups/
```
The backup utility uses SQLite's backup API so the live WAL database can remain in use during the backup. Each backup is checked with `PRAGMA quick\_check`. By default the newest 14 backups are retained.
Custom example:
```bash
darktsunami-backup --keep 30
```
When systemd user services are available, the installer enables a persistent daily backup timer unless `--no-backup-timer` is supplied.
Health check
Run the dashboard collector without starting the GUI:
```bash
darktsunami-dashboard --check
```
It prints a JSON snapshot and exits non-zero if the database is unavailable or invalid.
Tests
From the unpacked project directory:
```bash
./test\_game.py
```
The test suite verifies:
identification-required behavior
deterministic LXMF address derivation
separate persistent LXMF players
DarkTsunami Keep branding
ASCII output
production metadata
activity logging
shared roster
tavern posting
party creation and joining
shared raid HP
asynchronous duel completion
dashboard collection
backup integrity
A successful run prints:
```text
DarkTsunami Keep production multiplayer tests: PASS
```
Uninstall
```bash
./uninstall.sh
```
The uninstall script removes the application files, dashboard launcher, autostart entry and backup timer. It deliberately preserves:
```text
\~/.nomadnetwork/storage/pages/.darktsunami\_keep/
```
so player data is not destroyed accidentally.
