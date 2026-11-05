# Inspecting App Data with sqlite3

SwiftData persists everything to a normal **SQLite** database (it's Core Data under
the hood). That means you can explore your data with any SQLite client — the
`sqlite3` CLI that ships with macOS, or a GUI like TablePlus / DB Browser for SQLite —
instead of only seeing it through the app.

This guide covers two cases:

1. [Simulator](#1-simulator) — the database is a live file on your Mac.
2. [Physical iPhone](#2-physical-iphone) — you download a snapshot of the app's
   container through Xcode, then open the database from that snapshot.

The app's bundle identifier is **`bradlet.Hybrid-AIthletics`** throughout.

---

## Quick start: the helper script

The repo ships [`scripts/inspect-store.sh`](../scripts/inspect-store.sh), which does
the locating, safe-copying, and name-decoding for you. It opens an `sqlite3` session
against a **copy** of the store (the live database is never touched) and defines two
readable views:

- `exercises` — one row per `Exercise`, with the `Z`-names cleaned up, the date
  converted, and a `completed` flag.
- `workouts` — one row per *recorded* exercise, with the nested workout JSON decoded
  into columns (`actual_mi`, `rpe`, `source`, `external_id`, …).

```bash
# Booted simulator's installed app:
scripts/inspect-store.sh

# Then, at the sqlite3 prompt:
SELECT * FROM workouts ORDER BY date DESC;
SELECT name, date, completed FROM exercises WHERE series_id IS NOT NULL ORDER BY series_id, date;

# One-off query without entering the prompt:
scripts/inspect-store.sh -q "SELECT COUNT(*) AS done FROM workouts;"

# A container downloaded from a physical device (see §2):
scripts/inspect-store.sh ~/Downloads/HybridAIthletics.xcappdata
```

The rest of this doc explains what the script does under the hood, so you can also
do it by hand or in a GUI.

---

## Background: what the database looks like

Because SwiftData sits on Core Data, the SQLite schema is **mangled**, not the clean
names from the Swift models. Knowing the three quirks below makes the raw tables
readable:

| Quirk | What you'll see | How to deal with it |
|-------|-----------------|---------------------|
| **`Z`-prefixed names** | `ZEXERCISE`, `ZAPPCONFIGURATION`, columns like `ZNAME`, `ZDISTANCEMILES`. Plus bookkeeping columns `Z_PK` (primary key), `Z_ENT`, `Z_OPT`. | Query `ZEXERCISE` instead of `Exercise`; ignore `Z_PK`/`Z_ENT`/`Z_OPT`. |
| **Core Data dates** | `ZDATE` is a float of *seconds since 2001-01-01 UTC*, not the Unix epoch. | Add `978307200` and convert: `datetime(ZDATE + 978307200, 'unixepoch', 'localtime')`. |
| **Nested `workout` is a JSON blob** | `ZWORKOUTDATA` is a `BLOB` containing the JSON-encoded `Workout` value (see [DATA_MODEL.md](DATA_MODEL.md)). `NULL` means the exercise is planned-only. | Read as text with `CAST(ZWORKOUTDATA AS TEXT)`, or pull fields with `json_extract(...)`. |

The `Exercise` table (`ZEXERCISE`) columns map like this:

```
ZNAME            → name
ZTYPE            → type (raw string, e.g. "Tempo Run")
ZDURATIONSECONDS → durationSeconds (planned target)
ZDISTANCEMILES   → distanceMiles   (planned target)
ZNOTES           → notes
ZDATE            → date            (Core Data epoch — see above)
ZSERIESID        → seriesID        (UUID blob, NULL = one-off)
ZCOUNTSTOWARDMILEAGE → countsTowardMileage (0/1)
ZID              → id (UUID, stored as a blob)
ZWORKOUTDATA     → workout         (JSON blob, NULL = planned only)
```

> **Read, don't write.** Editing rows by hand while the app or CloudKit sync is
> running risks store corruption and CloudKit desync. For safe poking, open
> read-only (`sqlite3 -readonly …`) or work on a copy. See
> [Working safely](#working-safely).

---

## 1. Simulator

On a booted simulator the store is a live file on disk. Let `simctl` locate the
app's data container so you don't have to chase the random UUIDs in the path:

```bash
# Resolve the data container of the app on the booted simulator
APP=$(xcrun simctl get_app_container booted "bradlet.Hybrid-AIthletics" data)

# Open an interactive sqlite3 session against the store
sqlite3 "$APP/Library/Application Support/default.store"
```

If `simctl` prints nothing, the app isn't installed on the *booted* sim (run it
once from Xcode), or no simulator is booted (`xcrun simctl list devices booted`).

Inside the `sqlite3> ` prompt, some useful starters:

```sql
.tables                       -- list tables (look for ZEXERCISE, ZAPPCONFIGURATION)
.mode column
.headers on
PRAGMA table_info(ZEXERCISE); -- column names + types
```

A query that un-mangles the names and decodes the nested workout:

```sql
SELECT ZNAME                                                      AS name,
       datetime(ZDATE + 978307200, 'unixepoch', 'localtime')      AS date,
       ZDISTANCEMILES                                             AS planned_mi,
       json_extract(CAST(ZWORKOUTDATA AS TEXT), '$.distanceMiles') AS actual_mi,
       json_extract(CAST(ZWORKOUTDATA AS TEXT), '$.feeling')       AS feeling,
       json_extract(CAST(ZWORKOUTDATA AS TEXT), '$.perceivedExertion') AS rpe,
       json_extract(CAST(ZWORKOUTDATA AS TEXT), '$.source')        AS source,
       (ZWORKOUTDATA IS NOT NULL)                                  AS completed
FROM ZEXERCISE
ORDER BY ZDATE DESC;
```

One-liner without entering the prompt:

```bash
sqlite3 -header -column "$APP/Library/Application Support/default.store" \
  "SELECT ZNAME, hex(ZSERIESID) AS series, (ZWORKOUTDATA IS NOT NULL) AS completed FROM ZEXERCISE ORDER BY ZDATE DESC;"
```

### A note on the `-wal` / `-shm` files

Next to `default.store` you'll see `default.store-wal` and `default.store-shm`.
The **WAL** (write-ahead log) holds writes the app hasn't checkpointed into the
main file yet. The `sqlite3` CLI reads the WAL automatically, so the live file
gives you current data. (This matters for GUI tools and copies — see below.)

> **Heads-up:** UI tests don't touch this file. Launching with `-uiTestSeed` uses
> an in-memory container, so test fixtures never appear in `default.store`.

---

## 2. Physical iPhone

There's no live filesystem path to a device's app container, so you take a
**snapshot** through Xcode, then open the database from inside it.

### Step 1 — Download the container

1. Plug in the iPhone and open Xcode.
2. **Window ▸ Devices and Simulators** (⇧⌘2), select your iPhone.
3. Under **Installed Apps**, select **Hybrid AIthletics**.
4. Click the **⋯ / gear** button below the list → **Download Container…**
5. Save the `.xcappdata` bundle somewhere (e.g. `~/Downloads`).

(CLI equivalent, if you prefer: `xcrun devicectl device copy from --device <UDID>
--domain-type appDataContainer --domain-identifier bradlet.Hybrid-AIthletics
--source / --destination ~/Downloads/HybridAIthletics.xcappdata`.)

### Step 2 — Find the store inside the snapshot

A `.xcappdata` is just a folder. Reveal it in Finder (right-click → **Show Package
Contents**) or use the shell:

```bash
BUNDLE=~/Downloads/HybridAIthletics.xcappdata     # adjust to your saved name
find "$BUNDLE" -name "default.store" -print
```

The store lives at roughly
`…/AppData/Library/Application Support/default.store`.

### Step 3 — Open it

Identical to the simulator from here — point `sqlite3` at the file the `find`
turned up:

```bash
STORE=$(find "$BUNDLE" -name "default.store" -print -quit)
sqlite3 -readonly "$STORE"
```

The same queries from [§1](#1-simulator) apply. Because this is a **copied
snapshot**, editing it does nothing to the phone — but it also means the data is
frozen at download time. Re-download to refresh.

> The snapshot includes `default.store-wal`/`-shm` alongside the store, so the WAL
> data comes along — `sqlite3` will read it.

---

## Working safely

- **Prefer read-only:** `sqlite3 -readonly "$STORE"`. You can still run every
  `SELECT`; it just blocks accidental writes.
- **Or work on a copy.** If you want to be completely isolated from the running
  app, copy all three files together (the WAL/SHM matter):
  ```bash
  cp "$APP/Library/Application Support/default.store"* /tmp/
  sqlite3 /tmp/default.store
  ```
- **Never hand-edit a CloudKit-synced store while the app runs.** SwiftData +
  CloudKit track changes through their own bookkeeping (the `ACHANGE` /
  `ATRANSACTION` tables you'll see). Writing rows directly bypasses that and can
  desync or corrupt the store. To reset data, prefer wiping from the app /
  CloudKit dashboard.

---

## GUI clients (optional)

If you'd rather browse than type SQL, point either of these at the same
`default.store` file:

- **DB Browser for SQLite** — free. `brew install --cask db-browser-for-sqlite`
- **TablePlus** — slicker, free tier covers a single connection.
  `brew install --cask tableplus`

For a GUI, **quit the app first** (or open a copy that includes the `-wal`/`-shm`
files), since GUI tools don't always replay the WAL the way the CLI does.
